//
//  StudentDiscovery.swift
//  SkillSwap
//
//  Phase B — real student discovery from the existing normalized Supabase
//  schema (profiles + student_skills + skills). Read-only; RLS-scoped; excludes
//  the signed-in student. Carries real profile ids and skill ids so Phase C can
//  create exchanges. No fabricated data, no schema changes.
//

import SwiftUI
import Combine
import Supabase

// MARK: - Models

/// A real catalog skill reference (id carried through for Phase C exchanges).
struct CatalogSkill: Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String
}

/// A real registered student assembled from profiles + student_skills.
struct DiscoveredStudent: Identifiable, Hashable {
    let id: String                // profiles.id (uuid string) — real
    let name: String
    let major: String
    let bio: String
    let avatarURL: String?
    let teaches: [CatalogSkill]
    let learns: [CatalogSkill]
    /// Teaching skill name -> experience-level slug (Phase D4; empty when none set).
    var teachingLevels: [String: String] = [:]
    var teachingExperienceBySkillID: [Int: String] = [:]
    /// Phase D5: accepting new exchanges? (slug; default open).
    var availabilityStatus: String = "open"

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = parts.map(String.init).joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    /// Categories this student touches (teach + learn) — used by Explore filters.
    var categories: Set<String> { Set((teaches + learns).map(\.category)) }

    /// Adapter to the existing card view model (filled with REAL data, so the
    /// approved HomeStudentCard renders unchanged). bannerColors vary by index.
    func card(colorIndex: Int) -> MockStudent {
        MockStudent(
            id: id, name: name, major: major, initials: initials,
            teaches: teaches.map(\.name), learns: learns.map(\.name),
            availability: "", category: categories.first ?? "",
            bannerColors: HomeGradients.studentPair(colorIndex),
            avatarURL: avatarURL, localImageName: nil
        )
    }
}

/// A real saved availability slot (day + time window) for a student.
struct AvailabilitySlot: Identifiable, Hashable {
    let id = UUID()
    let day: String            // stored abbreviation: "Sun"…"Sat"
    let startTime: String?     // "HH:mm:ss"
    let endTime: String?
}

// MARK: - Service (read-only)

struct StudentDiscoveryService {

    private let client = SupabaseManager.client

    /// Real availability for a specific student, fetched by their UUID. This is
    /// a normal authenticated SELECT — it does NOT bypass RLS; the availability
    /// table's row-level policy governs what comes back. Fetched on demand (only
    /// when a profile is opened), so it adds no cost to Home/Explore lists.
    func fetchAvailability(studentID: String) async throws -> [AvailabilitySlot] {
        struct Row: Decodable {
            let dayOfWeek: String
            let startTime: String?
            let endTime: String?
            enum CodingKeys: String, CodingKey {
                case dayOfWeek = "day_of_week"
                case startTime = "start_time"
                case endTime = "end_time"
            }
        }
        let rows: [Row] = try await client
            .from("availability")
            .select("day_of_week, start_time, end_time")
            .eq("student_id", value: studentID)
            .execute()
            .value

        let order = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return rows
            .map { AvailabilitySlot(day: $0.dayOfWeek, startTime: $0.startTime, endTime: $0.endTime) }
            .sorted { a, b in
                let ia = order.firstIndex(of: a.day) ?? order.count
                let ib = order.firstIndex(of: b.day) ?? order.count
                if ia != ib { return ia < ib }
                return (a.startTime ?? "") < (b.startTime ?? "")
            }
    }

    func fetchDiscoverableStudents() async throws -> [DiscoveredStudent] {
        struct PageParameters: Encodable {
            let p_after: String?
            let p_limit = 100
        }

        _ = try await client.auth.session
        let rows: [ProfileRow] = try await fetchPages(id: \.id) { cursor in
            try await client.rpc("discover_students", params: PageParameters(p_after: cursor))
                .order("id").execute().value
        }
        return students(from: rows)
    }

    func fetchProfile(id: UUID) async throws -> DiscoveredStudent? {
        try await fetchProfiles(ids: [id]).first
    }

    func fetchProfiles(ids: Set<UUID>) async throws -> [DiscoveredStudent] {
        guard !ids.isEmpty else { return [] }
        let me = try await client.auth.session.user.id
        let requested = ids.subtracting([me]).map(\.uuidString).sorted()
        var rows: [ProfileRow] = []
        for start in stride(from: 0, to: requested.count, by: 50) {
            let batch = Array(requested[start..<min(start + 50, requested.count)])
            let page: [ProfileRow] = try await fetchPages(id: \.id) { cursor in
                let query = client.from("profiles")
                    .select("id, full_name, major, bio, avatar_url, availability_status, skill_links:student_skills!student_skills_student_id_fkey(skill_type, experience_level, skills(id, name, category))")
                    .in("id", values: batch)
                if let cursor { _ = query.gt("id", value: cursor) }
                return try await query.order("id").limit(50).execute().value
            }
            rows.append(contentsOf: page)
        }
        return students(from: rows)
    }

    private func students(from rows: [ProfileRow]) -> [DiscoveredStudent] {
        rows.compactMap { row -> DiscoveredStudent? in
            let name = (row.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            var teaches: [CatalogSkill] = []
            var learns: [CatalogSkill] = []
            var levels: [String: String] = [:]
            var experience: [Int: String] = [:]
            for link in row.skillLinks {
                guard let skill = link.skills else { continue }
                let reference = CatalogSkill(id: skill.id, name: skill.name, category: skill.category)
                switch link.skillType {
                case "teach":
                    teaches.append(reference)
                    if let level = link.experienceLevel {
                        levels[skill.name] = level
                        experience[skill.id] = level
                    }
                case "learn":
                    learns.append(reference)
                default:
                    break
                }
            }
            return DiscoveredStudent(
                id: row.id, name: name, major: row.major ?? "", bio: row.bio ?? "",
                avatarURL: (row.avatarURL?.isEmpty == false) ? row.avatarURL : nil,
                teaches: teaches.sorted(by: Self.skillOrder), learns: learns.sorted(by: Self.skillOrder),
                teachingLevels: levels, teachingExperienceBySkillID: experience,
                availabilityStatus: row.availabilityStatus ?? "open"
            )
        }.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    func fetchCatalog() async throws -> [CatalogSkill] {
        _ = try await client.auth.session
        let rows: [SkillRow] = try await fetchPages(id: \.id) { (cursor: Int?) in
            let query = client.from("skills").select("id, name, category")
            if let cursor { _ = query.gt("id", value: cursor) }
            return try await query.order("id").limit(200).execute().value
        }
        return rows.map { CatalogSkill(id: $0.id, name: $0.name, category: $0.category) }
            .sorted(by: Self.skillOrder)
    }

    // A short page can reflect the API's row cap. Only an empty page ends the scan.
    private func fetchPages<Row, ID: Comparable>(
        id: KeyPath<Row, ID>,
        page: (ID?) async throws -> [Row]
    ) async throws -> [Row] {
        var rows: [Row] = []
        var cursor: ID?
        while true {
            try Task.checkCancellation()
            let next = try await page(cursor)
            guard !next.isEmpty else { return rows }
            for row in next {
                let key = row[keyPath: id]
                if let cursor, key <= cursor { throw PaginationError.invalidOrder }
                cursor = key
                rows.append(row)
            }
        }
    }

    private enum PaginationError: Error {
        case invalidOrder
    }

    private nonisolated static func skillOrder(_ lhs: CatalogSkill, _ rhs: CatalogSkill) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    // Decoding
    private struct ProfileRow: Decodable {
        let id: String
        let fullName: String?
        let major: String?
        let bio: String?
        let avatarURL: String?
        let availabilityStatus: String?
        let skillLinks: [SkillLink]
        enum CodingKeys: String, CodingKey {
            case id, major, bio
            case fullName = "full_name"
            case avatarURL = "avatar_url"
            case skillLinks = "skill_links"
            case availabilityStatus = "availability_status"
        }
    }
    private struct SkillLink: Decodable {
        let skillType: String
        let experienceLevel: String?
        let skills: SkillRow?
        enum CodingKeys: String, CodingKey {
            case skills
            case skillType = "skill_type"
            case experienceLevel = "experience_level"
        }
    }
    private struct SkillRow: Decodable { let id: Int; let name: String; let category: String }
}

// MARK: - Shared directory (loaded once, observed by discovery screens)

@MainActor
final class StudentDirectory: ObservableObject {

    @Published private(set) var students: [DiscoveredStudent] = []
    @Published private(set) var isLoading = false
    @Published var loadError: String?

    @Published private(set) var hasLoaded = false

    private let service = StudentDiscoveryService()
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Force a reload (e.g. pull-to-refresh) so updated profiles/avatars appear.
    func refresh() async { await load() }

    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }

        isLoading = true
        students = []
        hasLoaded = false
        loadError = nil
        let task = Task {
            defer { isLoading = false }
            do {
                students = try await service.fetchDiscoverableStudents()
                hasLoaded = true
                loadError = nil
            } catch {
                loadError = "We couldn't load students. Please try again."
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    func student(id: String) -> DiscoveredStudent? { students.first { $0.id == id } }
}
