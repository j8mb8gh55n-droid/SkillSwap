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

    func fetchStudents() async throws -> [DiscoveredStudent] {
        let me = try await client.auth.session.user.id.uuidString

        // 1. Other students' public profiles (RLS allows authenticated SELECT).
        let profiles: [ProfileRow] = try await client
            .from("profiles")
            .select("id, full_name, major, bio, avatar_url, availability_status")
            .neq("id", value: me)
            .order("full_name", ascending: true)
            .execute()
            .value

        // 2. Their teach/learn skills joined to the read-only skills catalog.
        let links: [SkillLink] = try await client
            .from("student_skills")
            .select("student_id, skill_type, experience_level, skills ( id, name, category )")
            .neq("student_id", value: me)
            .execute()
            .value

        var teachBy: [String: [CatalogSkill]] = [:]
        var learnBy: [String: [CatalogSkill]] = [:]
        var levelsBy: [String: [String: String]] = [:]
        for link in links {
            guard let s = link.skills else { continue }
            let ref = CatalogSkill(id: s.id, name: s.name, category: s.category)
            if link.skillType == "teach" {
                teachBy[link.studentID, default: []].append(ref)
                if let lvl = link.experienceLevel { levelsBy[link.studentID, default: [:]][s.name] = lvl }
            }
            else if link.skillType == "learn" { learnBy[link.studentID, default: []].append(ref) }
        }

        // Skip un-onboarded accounts (no name yet) so discovery shows real people.
        return profiles.compactMap { p in
            // Belt-and-suspenders: never recommend the signed-in user to
            // themselves, even if the server-side .neq ever changes/fails.
            guard p.id.caseInsensitiveCompare(me) != .orderedSame else { return nil }
            let name = (p.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return DiscoveredStudent(
                id: p.id, name: name, major: p.major ?? "", bio: p.bio ?? "",
                avatarURL: (p.avatarURL?.isEmpty == false) ? p.avatarURL : nil,
                teaches: teachBy[p.id] ?? [], learns: learnBy[p.id] ?? [],
                teachingLevels: levelsBy[p.id] ?? [:],
                availabilityStatus: p.availabilityStatus ?? "open"
            )
        }
    }

    // Decoding
    private struct ProfileRow: Decodable {
        let id: String
        let fullName: String?
        let major: String?
        let bio: String?
        let avatarURL: String?
        let availabilityStatus: String?
        enum CodingKeys: String, CodingKey {
            case id, major, bio
            case fullName = "full_name"
            case avatarURL = "avatar_url"
            case availabilityStatus = "availability_status"
        }
    }
    private struct SkillLink: Decodable {
        let studentID: String
        let skillType: String
        let experienceLevel: String?
        let skills: SkillRow?
        enum CodingKeys: String, CodingKey {
            case skills
            case studentID = "student_id"
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

    private let service = StudentDiscoveryService()
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Force a reload (e.g. pull-to-refresh) so updated profiles/avatars appear.
    func refresh() async { await load() }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            students = try await service.fetchStudents()
            hasLoaded = true
        } catch {
            print("[Discovery] load failed:", error)
            loadError = "We couldn't load students. Please try again."
        }
    }

    func student(id: String) -> DiscoveredStudent? { students.first { $0.id == id } }
}
