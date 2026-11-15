import Foundation

enum CommunityPostType: String, CaseIterable, Codable, Identifiable {
    case question, resource, project, tip

    var id: Self { self }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .question: "questionmark.bubble"
        case .resource: "link"
        case .project: "hammer"
        case .tip: "lightbulb"
        }
    }
}

struct CommunityPostItem: Decodable, Identifiable {
    struct Author: Decodable {
        let name: String

        enum CodingKeys: String, CodingKey {
            case name = "full_name"
        }
    }

    struct Skill: Decodable, Identifiable {
        let id: Int
        let name: String
    }

    struct SkillLink: Decodable {
        let skill: Skill
    }

    struct Bookmark: Decodable {
        let postID: UUID

        enum CodingKeys: String, CodingKey {
            case postID = "post_id"
        }
    }

    let id: UUID
    let authorID: UUID
    let author: Author
    let kind: CommunityPostType
    let title: String
    let body: String
    let externalURL: String?
    let createdAt: Date
    let updatedAt: Date
    let tagLinks: [SkillLink]
    let bookmarks: [Bookmark]

    var skills: [Skill] { tagLinks.map(\.skill).sorted { $0.name < $1.name } }
    var isSaved: Bool { !bookmarks.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, author, kind, title, body, bookmarks
        case authorID = "author_id"
        case externalURL = "external_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tagLinks = "tag_links"
    }
}

struct CommunityPostDraft {
    static let titleLimit = 120
    static let bodyLimit = 4_000
    static let tagLimit = 10

    var kind: CommunityPostType = .question
    var title = ""
    var body = ""
    var link = ""
    var skillIDs: Set<Int> = []

    init(post: CommunityPostItem? = nil) {
        guard let post else { return }
        kind = post.kind
        title = post.title
        body = post.body
        link = post.externalURL ?? ""
        skillIDs = Set(post.skills.map(\.id))
    }

    var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func httpsURL(_ value: String) -> URL? {
        let pattern = #"^https://([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(:443)?([/?#][^\s\p{Cc}\\]*)?$"#
        guard value.unicodeScalars.count <= 2048,
              value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return URL(string: value)
    }

    var validationError: String? {
        if cleanTitle.isEmpty || cleanTitle.unicodeScalars.count > Self.titleLimit {
            return "Enter a title between 1 and 120 characters."
        }
        if cleanBody.isEmpty || cleanBody.unicodeScalars.count > Self.bodyLimit {
            return "Enter text between 1 and 4,000 characters."
        }
        if !(1...Self.tagLimit).contains(skillIDs.count) { return "Choose 1 to 10 skills." }
        if !cleanLink.isEmpty && Self.httpsURL(cleanLink) == nil {
            return "Enter a valid HTTPS link, or leave the link blank."
        }
        return nil
    }
}

struct CommunityFeedFilters {
    enum Order: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case latest = "Latest"
        var id: Self { self }
    }

    var order: Order = .forYou
    var kind: CommunityPostType?
    var skillID: Int?
    var search = ""
    var savedOnly = false

    func results(from posts: [CommunityPostItem], learning: Set<Int>) -> [CommunityPostItem] {
        let query = Self.normalized(search)
        let filtered = posts.filter { post in
            (kind == nil || post.kind == kind)
                && (skillID == nil || post.skills.contains { $0.id == skillID })
                && (!savedOnly || post.isSaved)
                && (query.isEmpty || ([post.title, post.body] + post.skills.map(\.name))
                    .contains { Self.normalized($0).contains(query) })
        }
        return filtered.map { post in
            let score = order == .forYou ? learning.intersection(post.skills.map(\.id)).count : 0
            return (post, score)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.createdAt != rhs.0.createdAt { return lhs.0.createdAt > rhs.0.createdAt }
            return lhs.0.id.uuidString > rhs.0.id.uuidString
        }.map(\.0)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
