import Foundation

@main
struct CommunityPostTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        func post(_ suffix: Int, _ title: String, _ kind: String, _ created: String,
                  skillID: Int, skillName: String, bookmarked: Bool = false) throws -> CommunityPostItem {
            let id = "00000000-0000-0000-0000-00000000000\(suffix)"
            let bookmark = bookmarked ? "[{\"post_id\":\"\(id)\"}]" : "[]"
            let json = """
            {
              "id":"\(id)", "kind":"\(kind)", "author_id":"00000000-0000-0000-0000-000000000010",
              "author":{"full_name":"Student"}, "title":"\(title)", "body":"Example discussion",
              "external_url":"https://example.com/resource","created_at":"\(created)","updated_at":"\(created)",
              "tag_links":[{"skill":{"id":\(skillID),"name":"\(skillName)"}}], "bookmarks":\(bookmark)
            }
            """
            return try decoder.decode(CommunityPostItem.self, from: Data(json.utf8))
        }

        let fixture = try [
            post(1, "Café layout", "project", "2026-11-12T10:00:00Z", skillID: 2, skillName: "Python", bookmarked: true),
            post(2, "Typography", "resource", "2026-11-13T11:00:00Z", skillID: 5, skillName: "UI/UX Design"),
            post(3, "Setup", "question", "2026-11-13T11:00:00Z", skillID: 6, skillName: "Python"),
            post(4, "Shortcuts", "tip", "2026-11-13T10:00:00Z", skillID: 5, skillName: "UI/UX Design")
        ]
        func titles(_ rows: [CommunityPostItem]) -> [String] { rows.map(\.title) }

        var filters = CommunityFeedFilters()
        precondition(titles(filters.results(from: fixture, learning: [2])) == ["Café layout", "Setup", "Typography", "Shortcuts"])
        precondition(titles(filters.results(from: fixture, learning: [])) == ["Setup", "Typography", "Shortcuts", "Café layout"])
        filters.order = .latest
        precondition(titles(filters.results(from: fixture, learning: [2])) == ["Setup", "Typography", "Shortcuts", "Café layout"])
        filters.search = "  CAFE    LAYOUT "
        precondition(titles(filters.results(from: fixture, learning: [])) == ["Café layout"])
        filters.search = "example discussion"
        precondition(filters.results(from: fixture, learning: []).count == 4)
        filters.search = "ui/ux design"
        filters.skillID = 5
        filters.kind = .tip
        precondition(titles(filters.results(from: fixture, learning: [])) == ["Shortcuts"])
        filters.savedOnly = true
        precondition(filters.results(from: fixture, learning: []).isEmpty)
        filters = CommunityFeedFilters(savedOnly: true)
        precondition(titles(filters.results(from: fixture, learning: [])) == ["Café layout"])

        let author = try UUID(uuidString: "00000000-0000-0000-0000-000000000010").unwrap()
        precondition(fixture[0].authorID == author && fixture[0].isSaved && !fixture[1].isSaved)
        var draft = CommunityPostDraft(post: fixture[0])
        precondition(draft.kind == .project && draft.skillIDs == [2] && draft.validationError == nil)
        draft.skillIDs = []
        precondition(draft.validationError != nil)
        draft.skillIDs = [2]
        draft.title = String(repeating: "a", count: 121)
        precondition(draft.validationError != nil)
        draft.title = " Title "
        draft.body = String(repeating: "a", count: 4_001)
        precondition(draft.validationError != nil)
        draft.body = "Valid body"
        draft.link = " "
        precondition(draft.cleanTitle == "Title" && draft.validationError == nil)
        for invalid in ["http://example.com", "https://u@example.com", "https://example.com/a b",
                        "https://example.com/a\\b", "https://example.com:6666"] {
            precondition(CommunityPostDraft.httpsURL(invalid) == nil)
        }
        precondition(CommunityPostDraft.httpsURL("https://example.com/skills?q=python#intro") != nil)
        print("Community post models, validation, filtering, bookmarks, and deterministic ranking passed")
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw CocoaError(.coderInvalidValue) }
        return self
    }
}
