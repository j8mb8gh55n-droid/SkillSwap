import Combine
import Foundation
import Supabase

struct CommunityService {
    private let client = SupabaseManager.client
    private func fields(savedOnly: Bool = false) -> String {
        let bookmarkJoin = savedOnly ? "!inner" : ""
        return """
        id, author_id, kind, title, body, external_url, created_at, updated_at,
        author:profiles!community_posts_author_id_fkey(full_name),
        tag_links:community_post_skills(skill:skills(id, name)),
        bookmarks:community_saved_posts\(bookmarkJoin)(post_id)
        """
    }

    func fetchPosts(authorID: UUID? = nil, savedBy: UUID? = nil) async throws -> [CommunityPostItem] {
        var cursor: String?
        var posts: [CommunityPostItem] = []
        while true {
            try Task.checkCancellation()
            let query = client.from("community_posts").select(fields(savedOnly: savedBy != nil))
            if let savedBy { _ = query.eq("bookmarks.student_id", value: savedBy) }
            if let authorID { _ = query.eq("author_id", value: authorID) }
            if let cursor { _ = query.gt("id", value: cursor) }
            let page: [CommunityPostItem] = try await query.order("id").limit(100).execute().value
            if page.isEmpty { return posts }
            for post in page {
                let key = post.id.uuidString
                if let cursor, key <= cursor { throw CommunityError.invalidPage }
                cursor = key
                posts.append(post)
            }
        }
    }

    func fetchPost(id: UUID) async throws -> CommunityPostItem? {
        let posts: [CommunityPostItem] = try await client.from("community_posts").select(fields())
            .eq("id", value: id).limit(1).execute().value
        return posts.first
    }

    func savePost(_ draft: CommunityPostDraft, id: UUID?) async throws -> UUID {
        struct Parameters: Encodable {
            let p_kind: CommunityPostType
            let p_title: String
            let p_body: String
            let p_skill_ids: [Int]
            let p_external_url: String
            let p_post_id: UUID?
        }
        return try await client.rpc("community_save_post", params: Parameters(
            p_kind: draft.kind, p_title: draft.cleanTitle, p_body: draft.cleanBody,
            p_skill_ids: draft.skillIDs.sorted(), p_external_url: draft.cleanLink, p_post_id: id
        )).execute().value
    }

    func deletePost(id: UUID) async throws {
        let deleted: [IDRow] = try await client.from("community_posts").delete()
            .eq("id", value: id).select("id").execute().value
        guard deleted.first?.id == id else { throw CommunityError.unavailable }
    }

    func setBookmark(post: UUID, saved: Bool) async throws {
        struct Bookmark: Encodable { let post_id: UUID }
        if saved {
            try await client.from("community_saved_posts").upsert(
                Bookmark(post_id: post), onConflict: "student_id,post_id",
                returning: .minimal, ignoreDuplicates: true
            ).execute()
        } else {
            try await client.from("community_saved_posts").delete(returning: .minimal)
                .eq("post_id", value: post).execute()
        }
    }

    private struct IDRow: Decodable { let id: UUID }

    enum CommunityError: Error {
        case invalidPage, unavailable
    }
}

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var posts: [CommunityPostItem] = []
    @Published private(set) var skills: [CatalogSkill] = []
    @Published private(set) var matchSkills: ExploreMatchSkills?
    @Published private(set) var accountID: UUID?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var writing = false
    @Published private(set) var feedError = false
    @Published private(set) var skillError = false
    @Published private(set) var learningError = false

    private let service = CommunityService()
    var learning: Set<Int> { matchSkills?.learning ?? [] }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await refresh()
    }

    func refresh() async {
        guard !loading, !writing else { return }
        loading = true
        matchSkills = nil
        defer { loading = false }
        async let catalog: Void = refreshSkills()
        async let preferences: Void = refreshLearning()
        await refreshPosts()
        _ = await (catalog, preferences)
    }

    func refreshAuthoredPosts(authorID: UUID?) async {
        await refreshScopedPosts(authorID: authorID, savedOnly: false)
    }

    func refreshSavedPosts() async {
        await refreshScopedPosts(authorID: nil, savedOnly: true)
    }

    private func refreshScopedPosts(authorID: UUID?, savedOnly: Bool) async {
        guard !loading, !writing else { return }
        loading = true
        defer { loading = false }
        do {
            let viewer = try await SupabaseManager.client.auth.session.user.id
            let snapshot = try await service.fetchPosts(
                authorID: savedOnly ? nil : (authorID ?? viewer),
                savedBy: savedOnly ? viewer : nil
            )
            try Task.checkCancellation()
            accountID = viewer
            posts = snapshot
            loaded = true
            feedError = false
        } catch {
            if !Task.isCancelled { feedError = true }
        }
    }

    private func refreshPosts() async {
        do {
            accountID = try await SupabaseManager.client.auth.session.user.id
            let snapshot = try await service.fetchPosts()
            try Task.checkCancellation()
            posts = snapshot
            loaded = true
            feedError = false
        } catch {
            if !Task.isCancelled { feedError = true }
        }
    }

    func refreshSkills() async {
        do {
            skills = try await StudentDiscoveryService().fetchCatalog()
            skillError = false
        } catch {
            if !Task.isCancelled { skillError = true }
        }
    }

    private func refreshLearning() async {
        do {
            matchSkills = try await ProfileService().fetchMyExploreSkills()
            learningError = false
        } catch {
            if !Task.isCancelled {
                matchSkills = nil
                learningError = true
            }
        }
    }

    func post(id: UUID) -> CommunityPostItem? { posts.first { $0.id == id } }

    func revalidate(id: UUID) async throws {
        guard !loading, !writing else { return }
        let prior = post(id: id)
        let updated = try await service.fetchPost(id: id)
        try Task.checkCancellation()
        guard !loading, !writing, post(id: id)?.updatedAt == prior?.updatedAt,
              post(id: id)?.isSaved == prior?.isSaved else { return }
        replace(id: id, with: updated)
    }

    private func replace(id: UUID, with updated: CommunityPostItem?) {
        posts.removeAll { $0.id == id }
        if let updated { posts.append(updated) }
    }

    func save(_ draft: CommunityPostDraft, id: UUID?) async throws {
        guard !writing, !loading else { throw CommunityService.CommunityError.unavailable }
        writing = true
        defer { writing = false }
        let savedID = try await service.savePost(draft, id: id)
        await reloadAfterWrite(id: savedID)
    }

    func delete(id: UUID) async throws {
        guard !writing, !loading else { throw CommunityService.CommunityError.unavailable }
        writing = true
        defer { writing = false }
        try await service.deletePost(id: id)
        replace(id: id, with: nil)
    }

    func setSaved(_ value: Bool, id: UUID) async throws {
        guard !writing, !loading else { throw CommunityService.CommunityError.unavailable }
        writing = true
        defer { writing = false }
        try await service.setBookmark(post: id, saved: value)
        await reloadAfterWrite(id: id)
    }

    private func reloadAfterWrite(id: UUID) async {
        do {
            replace(id: id, with: try await service.fetchPost(id: id))
        } catch {
            feedError = true
        }
    }
}
