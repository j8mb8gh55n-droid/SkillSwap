//
//  StudentProfile.swift
//  SkillSwap
//

import Foundation
import SwiftUI

// MARK: - Profiles Row
// Mirrors public.profiles exactly. full_name / major / bio are
// NOT NULL DEFAULT '' in the database, so they always decode.

struct StudentProfile: Codable, Identifiable {

    let id: UUID

    var fullName: String
    var major: String
    var bio: String
    var avatarURL: String?
    /// Optional so a select that omits it still decodes (defaults to open in use).
    var availabilityStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case major
        case bio
        case avatarURL = "avatar_url"
        case availabilityStatus = "availability_status"
    }
}

// MARK: - Availability Status (Phase D5)
// Whether a student is currently accepting NEW exchange requests. Separate from
// weekly availability (days/times). Raw values are the DB slugs.

enum AvailabilityStatus: String, CaseIterable, Identifiable, Codable {

    case open
    case limited
    case unavailable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open:        return "Open"
        case .limited:     return "Limited"
        case .unavailable: return "Unavailable"
        }
    }

    /// Short helper text for profiles.
    var blurb: String {
        switch self {
        case .open:        return "Accepting new exchanges"
        case .limited:     return "Accepting a few new exchanges"
        case .unavailable: return "Not accepting new exchanges right now"
        }
    }

    /// Subtle pastel indicator (matches the approved palette).
    var tint: Color {
        switch self {
        case .open:        return Theme.mint
        case .limited:     return Theme.softPeach
        case .unavailable: return Theme.blush
        }
    }

    /// Open and Limited accept requests; Unavailable does not.
    var acceptsRequests: Bool { self != .unavailable }

    /// Map a stored slug (or nil) to a status, defaulting to .open.
    static func from(_ slug: String?) -> AvailabilityStatus {
        AvailabilityStatus(rawValue: slug ?? "open") ?? .open
    }
}

// MARK: - Skills Catalog Row
// Mirrors public.skills (read-only for app users).

struct Skill: Codable, Identifiable {

    let id: Int
    let name: String
    let category: String
}

// MARK: - Skill Experience Level (Phase D4)
// Applies only to skills a student TEACHES. Raw values are the DB slugs stored
// in student_skills.experience_level; `label` is the approved display text.

enum SkillExperienceLevel: String, CaseIterable, Identifiable, Codable {

    case gettingStarted = "getting_started"
    case comfortable    = "comfortable"
    case experienced    = "experienced"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .comfortable:    return "Comfortable"
        case .experienced:    return "Experienced"
        }
    }

    /// Display text for a stored slug, or nil when unset/unknown (graceful).
    static func label(forSlug slug: String?) -> String? {
        guard let slug, let level = SkillExperienceLevel(rawValue: slug) else { return nil }
        return level.label
    }
}

// MARK: - Loaded Profile (assembled from the normalized tables)

struct LoadedProfile {

    var fullName = ""
    var major = ""
    var bio = ""
    var avatarURL: String?

    var teachingSkills: [String] = []
    var learningSkills: [String] = []
    /// Teaching skill name -> experience-level slug (only skills with a level set).
    var teachingLevels: [String: String] = [:]
    var availabilityDays: [String] = []
    var availabilityStart: String = "09:00:00"
    var availabilityEnd: String = "10:00:00"
    /// Phase D5: whether the student is accepting new exchanges (slug; default open).
    var availabilityStatus: String = "open"
}

// MARK: - Save Result

struct ProfileSaveResult {

    /// Typed skill names that aren't in the read-only `skills` catalog,
    /// so they couldn't be stored. Surfaced to the student (never dropped
    /// silently).
    var unmatchedSkills: [String] = []
}
