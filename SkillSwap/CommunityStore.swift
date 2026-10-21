//
//  CommunityStore.swift
//  SkillSwap
//
//  Batch B: in-memory store for the Community tab. Holds the feed and supports
//  meaningful LOCAL interactions — appreciations, comments, and creating posts.
//
//  ⚠️ MOCK / LOCAL ONLY. Seeded from MockData; nothing here is persisted to
//  Supabase (the community backend is not built this sprint). State lives for
//  the app session. See DATA_SOURCES.md.
//

import SwiftUI
import Combine

// MARK: - Local author identity (stand-in for the signed-in user)

enum CommunityMe {
    static let name     = "You"
    static let initials = "YOU"
}

// MARK: - Models

struct CommunityComment: Identifiable {
    let id = UUID()
    let authorName: String
    let authorInitials: String
    let text: String
}

struct CommunityPostItem: Identifiable {
    let id: String
    let kind: CommunityPostKind
    let authorName: String
    let authorInitials: String
    let title: String
    let body: String
    let skillTags: [String]
    var appreciations: Int
    var likedByMe: Bool
    var comments: [CommunityComment]
    let bannerColors: [Color]
}

// MARK: - Store

@MainActor
final class CommunityStore: ObservableObject {

    @Published var posts: [CommunityPostItem]
    @Published var joinedChallenge = false

    init() {
        // Seed from MockData, adding a couple of sample comments for realism.
        posts = MockData.communityPosts.enumerated().map { index, p in
            CommunityPostItem(
                id: p.id,
                kind: p.kind,
                authorName: p.authorName,
                authorInitials: p.authorInitials,
                title: p.title,
                body: p.body,
                skillTags: p.skillTags,
                appreciations: p.appreciations,
                likedByMe: false,
                comments: index == 0
                    ? [
                        CommunityComment(authorName: "Lina Abdullah", authorInitials: "LA", text: "This is so inspiring! 🎉"),
                        CommunityComment(authorName: "Reem Fahad", authorInitials: "RF", text: "Congrats — the UI looks clean.")
                      ]
                    : [],
                bannerColors: p.bannerColors
            )
        }
    }

    // MARK: Appreciations

    func toggleAppreciation(_ id: String) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        if posts[i].likedByMe {
            posts[i].likedByMe = false
            posts[i].appreciations -= 1
        } else {
            posts[i].likedByMe = true
            posts[i].appreciations += 1
        }
    }

    // MARK: Comments

    func addComment(_ text: String, to id: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].comments.append(
            CommunityComment(
                authorName: CommunityMe.name,
                authorInitials: CommunityMe.initials,
                text: trimmed
            )
        )
    }

    func post(_ id: String) -> CommunityPostItem? {
        posts.first { $0.id == id }
    }

    // MARK: Create

    func addPost(kind: CommunityPostKind, title: String, body: String, tags: [String]) {
        let newPost = CommunityPostItem(
            id: "local-\(posts.count)-\(title.hashValue)",
            kind: kind,
            authorName: CommunityMe.name,
            authorInitials: CommunityMe.initials,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            skillTags: tags,
            appreciations: 0,
            likedByMe: false,
            comments: [],
            bannerColors: [Theme.lavender, Theme.softPink]
        )
        posts.insert(newPost, at: 0)
    }

    // MARK: Helpers

    /// Finds a mock student who teaches `skill` (for "The Skill Behind It").
    func studentsTeaching(_ skill: String) -> [MockStudent] {
        MockData.students.filter {
            $0.teaches.contains { $0.localizedCaseInsensitiveContains(skill) }
        }
    }

    /// Maps a post author to a known mock student (for "Teach Me This").
    func student(forAuthor name: String) -> MockStudent? {
        MockData.students.first { $0.name == name }
    }
}
