//
//  ProfileService.swift
//  SkillSwap
//

import Foundation
import Supabase

// MARK: - Profile Errors

enum ProfileServiceError: LocalizedError {

    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to access your profile."
        }
    }
}

// MARK: - Profile Service
// Adapts the app to the existing normalized Supabase schema:
//   profiles · skills · student_skills · availability
// It never alters the database structure or policies.

struct ProfileService {

    // MARK: - Supabase Client

    private let client = SupabaseManager.client

    /// Canonical weekday order for stable display.
    private let weekdayOrder = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: - Current User ID

    private func currentUserID() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }

    /// Full name stored in Supabase Auth user metadata (set at sign-up), if any.
    private static func metadataFullName(_ user: User) -> String? {
        if case let .string(name)? = user.userMetadata["full_name"] { return name }
        return nil
    }

    private struct DiscoverabilityPreference: Codable {
        let discoverable_in_explore: Bool
    }

    func fetchDiscoverability() async throws -> Bool {
        let userID = try await currentUserID()
        let preference: DiscoverabilityPreference = try await client.from("profiles")
            .select("discoverable_in_explore").eq("id", value: userID)
            .single().execute().value
        return preference.discoverable_in_explore
    }

    func saveDiscoverability(_ value: Bool) async throws -> Bool {
        let userID = try await currentUserID()
        let preference: DiscoverabilityPreference = try await client.from("profiles")
            .update(DiscoverabilityPreference(discoverable_in_explore: value))
            .eq("id", value: userID).select("discoverable_in_explore")
            .single().execute().value
        return preference.discoverable_in_explore
    }

    func fetchMyExploreSkills() async throws -> ExploreMatchSkills {
        enum SkillReadError: Error { case invalidPageOrder }

        struct Link: Decodable {
            let id: Int
            let skillID: Int
            let skillType: String

            enum CodingKeys: String, CodingKey {
                case id
                case skillID = "skill_id"
                case skillType = "skill_type"
            }
        }

        let userID = try await currentUserID()
        var cursor: Int?
        var teaching = Set<Int>()
        var learning = Set<Int>()
        while true {
            let query = client.from("student_skills")
                .select("id, skill_id, skill_type")
                .eq("student_id", value: userID)
            if let cursor { _ = query.gt("id", value: cursor) }
            let page: [Link] = try await query.order("id").limit(200).execute().value
            guard !page.isEmpty else { break }
            for link in page {
                if let cursor, link.id <= cursor { throw SkillReadError.invalidPageOrder }
                cursor = link.id
                if link.skillType == "teach" { teaching.insert(link.skillID) }
                if link.skillType == "learn" { learning.insert(link.skillID) }
            }
        }
        return ExploreMatchSkills(teaching: teaching, learning: learning)
    }

    // MARK: - Fetch (assemble from the normalized tables)

    func fetchMyProfile() async throws -> LoadedProfile {

        let session = try await AuthDiagnostics.trace("profileSession") {
            try await client.auth.session
        }
        let uid = session.user.id.uuidString

        // 1. profiles row
        let profileRows = try await AuthDiagnostics.trace("profiles", status: { $0.status }) {
            () async throws -> PostgrestResponse<[StudentProfile]> in
            try await client
                .from("profiles")
                .select("id, full_name, major, bio, avatar_url, availability_status")
                .eq("id", value: uid)
                .limit(1)
                .execute()
        }.value

        var loaded = LoadedProfile()

        if let profile = profileRows.first {
            loaded.fullName  = profile.fullName
            loaded.major     = profile.major
            loaded.bio       = profile.bio
            loaded.avatarURL = profile.avatarURL
            loaded.availabilityStatus = profile.availabilityStatus ?? "open"
        }

        // Backfill the name from signup metadata if the profile has none yet.
        // Works WITHOUT any DB change: the signed-in user updates their own row
        // (RLS-safe). Harmless once handle_new_user also populates full_name.
        if loaded.fullName.isEmpty, let metaName = Self.metadataFullName(session.user), !metaName.isEmpty {
            loaded.fullName = metaName
            _ = try? await client
                .from("profiles")
                .update(["full_name": metaName])
                .eq("id", value: uid)
                .execute()
        }

        // 2. student_skills joined to the skills catalog (incl. experience level)
        let skillRows = try await AuthDiagnostics.trace("student_skills", status: { $0.status }) {
            () async throws -> PostgrestResponse<[StudentSkillRow]> in
            try await client
                .from("student_skills")
                .select("skill_type, experience_level, skills(name)")
                .eq("student_id", value: uid)
                .execute()
        }.value

        let teachRows = skillRows.filter { $0.skillType == "teach" }
        loaded.teachingSkills = teachRows.compactMap { $0.skills?.name }
        loaded.learningSkills = skillRows
            .filter { $0.skillType == "learn" }
            .compactMap { $0.skills?.name }

        // Teaching skill name -> experience-level slug (only where one is set).
        loaded.teachingLevels = Dictionary(
            teachRows.compactMap { row -> (String, String)? in
                guard let name = row.skills?.name, let level = row.experienceLevel else { return nil }
                return (name, level)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // 3. availability (days only for the current UI)
        let availabilityRows = try await AuthDiagnostics.trace("availability", status: { $0.status }) {
            () async throws -> PostgrestResponse<[AvailabilityRow]> in
            try await client
                .from("availability")
                .select("day_of_week, start_time, end_time")
                .eq("student_id", value: uid)
                .execute()
        }.value

        let uniqueDays = Set(availabilityRows.map(\.dayOfWeek))
        loaded.availabilityDays = orderedDays(uniqueDays)
        if let first = availabilityRows.first {
            loaded.availabilityStart = first.startTime
            loaded.availabilityEnd = first.endTime
        }

        return loaded
    }

    // MARK: - Skill catalog (read-only)

    func fetchSkillCatalog() async throws -> [Skill] {
        try await client
            .from("skills")
            .select("id, name, category")
            .order("name", ascending: true)
            .execute()
            .value
    }

    // MARK: - Save (profile + student_skills + availability)

    /// Persists the student's own data. Returns any typed skill names that
    /// aren't in the read-only catalog, so the UI can report them.
    @discardableResult
    func saveMyProfile(
        fullName: String,
        major: String,
        bio: String,
        teachingSkills: [String],
        learningSkills: [String],
        availabilityDays: [String],
        teachingLevels: [String: String] = [:],
        startTime: String = "09:00:00",
        endTime: String = "10:00:00"
    ) async throws -> ProfileSaveResult {

        let userID = try await currentUserID()
        let uid = userID.uuidString

        // 1. Upsert the profiles row (works whether or not the trigger
        //    already created it).
        let profilePayload = ProfileUpsert(
            id: uid,
            full_name: fullName,
            major: major,
            bio: bio
        )

        try await client
            .from("profiles")
            .upsert(profilePayload)
            .execute()

        // 2. Map typed skill names to catalog IDs (catalog is read-only).
        let catalog: [Skill] = try await client
            .from("skills")
            .select("id, name, category")
            .execute()
            .value

        var idByName: [String: Int] = [:]
        for skill in catalog {
            idByName[skill.name.lowercased()] = skill.id
        }

        var unmatched: [String] = []

        func matchedIDs(_ names: [String]) -> [Int] {
            var ids: [Int] = []
            var seen = Set<Int>()
            for raw in names {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if let id = idByName[name.lowercased()] {
                    if seen.insert(id).inserted {
                        ids.append(id)
                    }
                } else if !unmatched.contains(where: {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }) {
                    unmatched.append(name)
                }
            }
            return ids
        }

        // Teach rows carry their chosen experience level (looked up by name).
        // Built directly (not via matchedIDs) so each re-inserted teach row keeps
        // its level — this is what stops a delete-then-insert save from erasing
        // previously selected levels.
        var teachInserts: [StudentSkillInsert] = []
        var seenTeach = Set<Int>()
        for raw in teachingSkills {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let id = idByName[name.lowercased()] {
                guard seenTeach.insert(id).inserted else { continue }
                let level = teachingLevels[name] ?? teachingLevels[name.lowercased()]
                teachInserts.append(StudentSkillInsert(
                    student_id: uid, skill_id: id, skill_type: "teach", experience_level: level))
            } else if !unmatched.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                unmatched.append(name)
            }
        }
        let learnIDs = matchedIDs(learningSkills)

        // 3. Replace this student's skills (delete-then-insert).
        try await client
            .from("student_skills")
            .delete()
            .eq("student_id", value: uid)
            .execute()

        let skillInserts =
            teachInserts
            + learnIDs.map {
                StudentSkillInsert(student_id: uid, skill_id: $0, skill_type: "learn", experience_level: nil)
            }

        if !skillInserts.isEmpty {
            try await client
                .from("student_skills")
                .insert(skillInserts)
                .execute()
        }

        // 4. Replace this student's availability (delete-then-insert).
        try await client
            .from("availability")
            .delete()
            .eq("student_id", value: uid)
            .execute()

        let days = orderedDays(Set(
            availabilityDays.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        ))

        let availabilityInserts = days.map {
            AvailabilityInsert(
                student_id: uid,
                day_of_week: $0,
                start_time: startTime,
                end_time: endTime
            )
        }

        if !availabilityInserts.isEmpty {
            try await client
                .from("availability")
                .insert(availabilityInserts)
                .execute()
        }

        return ProfileSaveResult(unmatchedSkills: unmatched)
    }

    // MARK: - Availability status (Phase D5)

    /// Updates ONLY the signed-in student's availability_status. Touches no other
    /// column, so weekly availability, skills, and personal info are untouched.
    func updateAvailabilityStatus(_ status: String) async throws {
        let uid = try await currentUserID().uuidString
        try await client
            .from("profiles")
            .update(["availability_status": status])
            .eq("id", value: uid)
            .execute()
    }

    // MARK: - Avatar upload (Supabase Storage)
    // Uploads to the "avatars" bucket at "<uid>/avatar.jpg" (users may only
    // write their own folder — enforced by the storage policies in
    // supabase/phase4_avatar_storage.sql) and stores the public URL in
    // profiles.avatar_url. Requires that bucket + policies to exist.

    func uploadAvatar(_ data: Data) async throws -> String {
        // IMPORTANT: Swift's UUID.uuidString is UPPERCASE, but the Storage RLS
        // policy compares the folder (text) to auth.uid()::text (LOWERCASE).
        // That comparison is case-sensitive, so the folder MUST be lowercase or
        // the INSERT is denied by RLS. (The profiles `id` compare is a UUID, so
        // it's case-insensitive — which is why profile saving already worked.)
        let uid = try await currentUserID().uuidString.lowercased()
        let path = "\(uid)/avatar.jpg"

        // Step 1 — upload the bytes to the "avatars" bucket. A failure here is
        // almost always a missing bucket or a Storage RLS policy (see
        // phase4_avatar_storage.sql). Log the real error; never a secret.
        do {
            try await client.storage
                .from("avatars")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        } catch {
            print("[Avatar] STEP 1 upload to bucket 'avatars' at '\(path)' failed:",
                  error.localizedDescription, "|", error)
            throw error
        }

        // Step 2 — resolve the public URL (cache-busted so the new image shows).
        let publicURL: URL
        do {
            publicURL = try client.storage.from("avatars").getPublicURL(path: path)
        } catch {
            print("[Avatar] STEP 2 getPublicURL failed:", error.localizedDescription, "|", error)
            throw error
        }
        let urlString = publicURL.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"

        // Step 3 — persist the URL to the student's own profiles row.
        do {
            try await client
                .from("profiles")
                .update(["avatar_url": urlString])
                .eq("id", value: uid)
                .execute()
        } catch {
            print("[Avatar] STEP 3 profiles.avatar_url update failed:",
                  error.localizedDescription, "|", error)
            throw error
        }

        return urlString
    }

    // MARK: - Helpers

    private func orderedDays(_ days: Set<String>) -> [String] {
        // Known weekdays first (canonical order), then any unexpected values.
        let known = weekdayOrder.filter { days.contains($0) }
        let extra = days
            .subtracting(weekdayOrder)
            .sorted()
        return known + extra
    }
}

// MARK: - Decoding Helpers (private to the service)

private struct StudentSkillRow: Decodable {

    let skillType: String
    let experienceLevel: String?
    let skills: SkillRef?

    enum CodingKeys: String, CodingKey {
        case skillType = "skill_type"
        case experienceLevel = "experience_level"
        case skills
    }
}

private struct SkillRef: Decodable {
    let name: String
}

private struct AvailabilityRow: Decodable {

    let dayOfWeek: String
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "day_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

// MARK: - Encoding Helpers (private to the service)

private struct ProfileUpsert: Encodable {
    let id: String
    let full_name: String
    let major: String
    let bio: String
}

private struct StudentSkillInsert: Encodable {
    let student_id: String
    let skill_id: Int
    let skill_type: String
    let experience_level: String?

    // Encode experience_level ALWAYS (as null when nil), not encodeIfPresent —
    // a batch insert requires every row to carry the identical set of keys, or
    // PostgREST rejects it ("All object keys must match").
    enum CodingKeys: String, CodingKey { case student_id, skill_id, skill_type, experience_level }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(student_id, forKey: .student_id)
        try c.encode(skill_id, forKey: .skill_id)
        try c.encode(skill_type, forKey: .skill_type)
        try c.encode(experience_level, forKey: .experience_level)
    }
}

private struct AvailabilityInsert: Encodable {
    let student_id: String
    let day_of_week: String
    let start_time: String
    let end_time: String
}
