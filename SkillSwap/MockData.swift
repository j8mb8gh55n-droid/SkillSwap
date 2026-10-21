//
//  MockData.swift
//  SkillSwap
//
//  ⚠️ MOCK DATA — NOT backed by Supabase.
//
//  Single source of truth for all hardcoded/sample content used by sprint
//  screens that are not yet connected to the backend. Keeping it here (rather
//  than inline in views) makes the real-vs-mock boundary explicit and easy to
//  swap for live data later. See DATA_SOURCES.md for the real/mock ledger.
//

import SwiftUI

// MARK: - Mock Models

struct MockStudent: Identifiable {
    let id: String
    let name: String
    let major: String
    let initials: String
    let teaches: [String]
    let learns: [String]
    let availability: String
    let category: String
    let bannerColors: [Color]
    /// Real Supabase avatar URL when available (nil for mock students).
    var avatarURL: String? = nil
    /// ⚠️ TEMPORARY TEST ONLY — bundled asset name. Remove to revert.
    var localImageName: String? = nil
}

enum CommunityPostKind: String {
    case madeIt    = "Made It"
    case swapStory = "Swap Story"
    case skillSnap = "SkillSnap"

    var symbol: String {
        switch self {
        case .madeIt:    return "checkmark.seal.fill"
        case .swapStory: return "arrow.left.arrow.right"
        case .skillSnap: return "play.rectangle.fill"
        }
    }
}

struct CommunityPost: Identifiable {
    let id: String
    let kind: CommunityPostKind
    let authorName: String
    let authorInitials: String
    let title: String
    let body: String
    let skillTags: [String]
    let appreciations: Int
    let comments: Int
    let bannerColors: [Color]
}

struct SkillChallenge: Identifiable {
    let id: String
    let month: String
    let title: String
    let detail: String
    let participants: Int
}

struct KudosItem: Identifiable {
    let id: String
    let fromName: String
    let fromInitials: String
    let skill: String
    let message: String
}

struct AchievementBadge: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let detail: String
    let earned: Bool
    let color: Color
}

struct DemandSkill: Identifiable {
    var id: String { skill }
    let skill: String
    let seekers: Int
    let category: String
}

enum SkillLevel: String, CaseIterable {
    case beginner     = "Beginner"
    case intermediate = "Intermediate"
    case advanced     = "Advanced"
}

struct ExperienceEntry: Identifiable {
    let id: String
    let skill: String
    let level: SkillLevel
}

// MARK: - Mock Data Store

enum MockData {

    // Students (Explore / Home discovery). Mirrors the existing sample roster.
    static let students: [MockStudent] = [
        MockStudent(
            id: "sara", name: "Sara Ahmed", major: "Computer Science", initials: "SA",
            teaches: ["Swift Programming"], learns: ["UI/UX Design"],
            availability: "Sun, Tue", category: "Technology",
            bannerColors: [Color(red: 0.73, green: 0.68, blue: 1.0), Color(red: 0.94, green: 0.76, blue: 0.94)]
        ),
        MockStudent(
            id: "lina", name: "Lina Abdullah", major: "Information Systems", initials: "LA",
            teaches: ["Python"], learns: ["Graphic Design"],
            availability: "Sun, Wed", category: "Technology",
            bannerColors: [Color(red: 0.62, green: 0.82, blue: 0.95), Color(red: 0.72, green: 0.90, blue: 0.84)]
        ),
        MockStudent(
            id: "nora", name: "Nora Khalid", major: "Digital Media", initials: "NK",
            teaches: ["Photography"], learns: ["Web Development"],
            availability: "Mon, Thu", category: "Creative",
            bannerColors: [Color(red: 1.0, green: 0.76, blue: 0.65), Color(red: 0.98, green: 0.65, blue: 0.77)],
            localImageName: "TestStudentPhoto"   // ⚠️ TEMP TEST
        ),
        MockStudent(
            id: "reem", name: "Reem Fahad", major: "Graphic Design", initials: "RF",
            teaches: ["UI/UX Design"], learns: ["Swift Programming"],
            availability: "Tue, Thu", category: "Design",
            bannerColors: [Color(red: 0.98, green: 0.79, blue: 0.87), Color(red: 1.0, green: 0.87, blue: 0.76)]
        ),
        MockStudent(
            id: "maha", name: "Maha Ali", major: "English Language", initials: "MA",
            teaches: ["English Conversation"], learns: ["Photography"],
            availability: "Sun, Mon", category: "Languages",
            bannerColors: [Color(red: 0.76, green: 0.91, blue: 0.83), Color(red: 0.84, green: 0.94, blue: 0.78)]
        ),
        MockStudent(
            id: "hala", name: "Hala Omar", major: "Mathematics", initials: "HO",
            teaches: ["Calculus"], learns: ["Python"],
            availability: "Wed, Thu", category: "Academics",
            bannerColors: [Color(red: 1.0, green: 0.88, blue: 0.70), Color(red: 1.0, green: 0.82, blue: 0.65)]
        )
    ]

    // Community feed content.
    static let communityPosts: [CommunityPost] = [
        CommunityPost(
            id: "post-1", kind: .madeIt,
            authorName: "Sara Ahmed", authorInitials: "SA",
            title: "Shipped my first iOS app!",
            body: "After swapping Swift lessons for design feedback, I finally launched my habit tracker on TestFlight.",
            skillTags: ["Swift Programming", "UI/UX Design"],
            appreciations: 42, comments: 8,
            bannerColors: [Color(red: 0.73, green: 0.68, blue: 1.0), Color(red: 0.94, green: 0.76, blue: 0.94)]
        ),
        CommunityPost(
            id: "post-2", kind: .swapStory,
            authorName: "Lina Abdullah", authorInitials: "LA",
            title: "Python ↔ Graphic Design",
            body: "We met twice a week for a month. I taught data viz, she taught me color theory. Best trade ever.",
            skillTags: ["Python", "Graphic Design"],
            appreciations: 31, comments: 5,
            bannerColors: [Color(red: 0.62, green: 0.82, blue: 0.95), Color(red: 0.72, green: 0.90, blue: 0.84)]
        ),
        CommunityPost(
            id: "post-3", kind: .skillSnap,
            authorName: "Nora Khalid", authorInitials: "NK",
            title: "60-second: golden-hour portraits",
            body: "A quick SkillSnap on using natural light for portraits — no fancy gear needed.",
            skillTags: ["Photography"],
            appreciations: 58, comments: 12,
            bannerColors: [Color(red: 1.0, green: 0.76, blue: 0.65), Color(red: 0.98, green: 0.65, blue: 0.77)]
        )
    ]

    static let currentChallenge = SkillChallenge(
        id: "challenge-oct",
        month: "October",
        title: "Teach one thing you love",
        detail: "Post a SkillSnap teaching a skill in under 60 seconds. Top three get featured next month.",
        participants: 126
    )

    // Profile extras (mock until the community/stats backend exists).
    static let kudos: [KudosItem] = [
        KudosItem(id: "k1", fromName: "Lina Abdullah", fromInitials: "LA", skill: "Swift Programming",
                  message: "Patient, clear, and genuinely kind. Learned so much!"),
        KudosItem(id: "k2", fromName: "Reem Fahad", fromInitials: "RF", skill: "Problem Solving",
                  message: "Helped me debug for an hour without judgment. Legend.")
    ]

    static let badges: [AchievementBadge] = [
        AchievementBadge(id: "b1", name: "First Swap", symbol: "sparkles", detail: "Completed your first exchange", earned: true, color: Color(red: 0.83, green: 0.79, blue: 1.0)),
        AchievementBadge(id: "b2", name: "Mentor", symbol: "lightbulb.fill", detail: "Taught 5 students", earned: true, color: Color(red: 1.0, green: 0.87, blue: 0.91)),
        AchievementBadge(id: "b3", name: "Curious Mind", symbol: "book.fill", detail: "Learned 5 new skills", earned: false, color: Color(red: 0.84, green: 0.94, blue: 0.86)),
        AchievementBadge(id: "b4", name: "Community Star", symbol: "star.fill", detail: "Received 25 kudos", earned: false, color: Color(red: 1.0, green: 0.88, blue: 0.70))
    ]

    static let experience: [ExperienceEntry] = [
        ExperienceEntry(id: "e1", skill: "Python", level: .advanced),
        ExperienceEntry(id: "e2", skill: "Problem Solving", level: .intermediate),
        ExperienceEntry(id: "e3", skill: "Public Speaking", level: .beginner)
    ]

    // Headline numbers for the profile stats row.
    static let completedExchanges = 7
    static let teachingHours = 14
    static let kudosReceived = 23

    // Skills many students want to learn right now (Home → Skills in Demand).
    static let skillsInDemand: [DemandSkill] = [
        DemandSkill(skill: "UI/UX Design",        seekers: 34, category: "Design"),
        DemandSkill(skill: "Swift Programming",   seekers: 28, category: "Technology"),
        DemandSkill(skill: "Photography",         seekers: 21, category: "Creative"),
        DemandSkill(skill: "Python",              seekers: 19, category: "Technology"),
        DemandSkill(skill: "English Conversation",seekers: 16, category: "Languages"),
        DemandSkill(skill: "Graphic Design",      seekers: 12, category: "Design")
    ]
}
