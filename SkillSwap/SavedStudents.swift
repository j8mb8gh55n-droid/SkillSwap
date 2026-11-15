//
//  SavedStudents.swift
//  SkillSwap
//
//  Local "Saved Students" bookmarks. There is no backend table for saved
//  students yet, so this persists on-device via UserDefaults (a real local
//  save — not fabricated server data). Injected app-wide by ContentView.
//

import SwiftUI
import Combine

@MainActor
final class SavedStudentsStore: ObservableObject {

    @Published private(set) var saved: Set<String> = []
    private let legacyKey = "saved_students"
    private var userKey: String?

    /// Scope bookmarks to the signed-in student (call once the user id is known).
    /// Bookmarks are now isolated per account — one user's saves never appear
    /// under another's.
    func use(userID: String) {
        let key = "saved_students_\(userID.lowercased())"
        userKey = key
        let defaults = UserDefaults.standard
        // One-time migration: move any pre-isolation (shared) bookmarks to this
        // user, then remove the shared key so they can't leak to other accounts.
        if defaults.object(forKey: key) == nil, let legacy = defaults.stringArray(forKey: legacyKey) {
            defaults.set(legacy, forKey: key)
            defaults.removeObject(forKey: legacyKey)
        }
        saved = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isSaved(_ id: String) -> Bool { saved.contains(id) }

    func toggle(_ id: String) {
        guard let userKey else { return }   // no-op until scoped to a user
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        UserDefaults.standard.set(Array(saved), forKey: userKey)
    }

    /// Stored bookmark count, including unavailable profiles.
    var count: Int { saved.count }
}

// MARK: - Bookmark button (isolated tap target for cards)

struct BookmarkButton: View {
    @EnvironmentObject private var saved: SavedStudentsStore
    let studentID: String
    var minimumTarget: CGFloat = 32

    var body: some View {
        let on = saved.isSaved(studentID)
        Button { saved.toggle(studentID) } label: {
            Image(systemName: on ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.charcoal)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .frame(width: minimumTarget, height: minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove from saved" : "Save student")
    }
}

// MARK: - Saved destination

struct SavedView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case students = "Students"
        case posts = "Posts"

        var id: Self { self }
    }

    @EnvironmentObject private var router: AppRouter
    @StateObject private var postStore = CommunityStore()
    @State private var segment: Segment = .students
    @State private var selectedPost: UUID?
    @EnvironmentObject private var saved: SavedStudentsStore
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [DiscoveredStudent] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var students: [DiscoveredStudent] { profiles.filter { saved.isSaved($0.id) } }

    private func load(_ ids: Set<String>) async {
        isLoading = true
        loadFailed = false
        profiles = []
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let found = try await StudentDiscoveryService().fetchProfiles(
                ids: Set(ids.compactMap { UUID(uuidString: $0) })
            )
            try Task.checkCancellation()
            profiles = found
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Picker("Saved content", selection: $segment) {
                        ForEach(Segment.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)

                    switch segment {
                    case .students: studentContent
                    case .posts: postContent
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                switch segment {
                case .students: await load(saved.saved)
                case .posts: await postStore.refreshSavedPosts()
                }
            }
        }
        .tint(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: saved.saved) { await load(saved.saved) }
        .task(id: segment) {
            if segment == .posts { await postStore.refreshSavedPosts() }
        }
        .navigationDestination(item: $selectedPost) { postID in
            PostDetailView(store: postStore, postID: postID)
                .task {
                    if postStore.post(id: postID)?.authorID == postStore.accountID &&
                        postStore.skills.isEmpty {
                        await postStore.refreshSkills()
                    }
                }
        }
    }

    @ViewBuilder private var studentContent: some View {
        if isLoading {
            loading("Loading saved students")
        } else if loadFailed {
            Text("Couldn’t load saved students.")
            Button("Retry") { Task { await load(saved.saved) } }
                .frame(minHeight: 44)
        } else if students.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No saved students yet.").font(Theme.Typography.headline)
                Button("Explore") {
                    dismiss()
                    router.openExplore()
                }
                .frame(minHeight: 44)
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(students) { student in row(student) }
            }
        }
    }

    @ViewBuilder private var postContent: some View {
        let posts = CommunityFeedFilters(order: .latest, savedOnly: true)
            .results(from: postStore.posts, learning: [])
        if postStore.feedError {
            Text("Couldn’t load saved posts.")
            Button("Retry") { Task { await postStore.refreshSavedPosts() } }
                .frame(minHeight: 44)
                .disabled(postStore.loading)
        } else if !postStore.loaded || (postStore.loading && posts.isEmpty) {
            loading("Loading saved posts")
        } else if posts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No saved posts yet.").font(Theme.Typography.headline)
                NavigationLink("Open Community") { CommunityView() }
                    .frame(minHeight: 44)
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    Button {
                        if selectedPost == nil { selectedPost = post.id }
                    } label: {
                        CommunityPostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loading(_ label: String) -> some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityLabel(label)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                BackChevron()
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Saved").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    private func row(_ s: DiscoveredStudent) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                destination(s).toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                HStack(spacing: 12) {
                    avatar(s)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.charcoal)
                        Text(s.major).font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            BookmarkButton(studentID: s.id, minimumTarget: 44)
        }
        .padding(14)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func avatar(_ s: DiscoveredStudent) -> some View {
        let size: CGFloat = 44
        if let url = s.avatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Monogram(initials: s.initials, size: size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(initials: s.initials, size: size)
        }
    }

    private func destination(_ s: DiscoveredStudent) -> StudentProfileView {
        StudentProfileView(student: s)
    }


}

// MARK: - Received Kudos (real — Supabase, recipient-visible)

struct KudosReceivedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReceivedKudos] = []
    @State private var isLoading = true
    @State private var loadError = false
    private let service = ExchangeService()

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isLoading {
                        HStack { Spacer(); ProgressView().tint(Theme.ink); Spacer() }.padding(.vertical, 40)
                    } else if loadError {
                        emptyState(icon: "exclamationmark.triangle", title: "Couldn't load kudos",
                                   message: "Please try again.")
                    } else if items.isEmpty {
                        emptyState(icon: "heart", title: "No kudos yet",
                                   message: "Kudos you receive after completed exchanges will appear here.")
                    } else {
                        ForEach(items) { kudosCard($0) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do { items = try await service.receivedKudos(); loadError = false }
        catch { print("[Kudos] receive load failed:", error); loadError = true }
        isLoading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                BackChevron()
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Kudos").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    private func kudosCard(_ k: ReceivedKudos) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar(k)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From \(k.giverName)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.charcoal)
                    if let d = k.createdAt {
                        Text(d.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                    }
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if !k.tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(k.tags, id: \.self) { tag in
                        Text(tag).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Theme.brightLavender.opacity(0.4)).clipShape(Capsule())
                    }
                }
            }
            if let m = k.message, !m.isEmpty {
                Text("“\(m)”").font(.system(size: 14)).foregroundStyle(Theme.charcoal.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    @ViewBuilder private func avatar(_ k: ReceivedKudos) -> some View {
        let size: CGFloat = 40
        if let url = k.giverAvatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Monogram(initials: k.giverInitials, size: size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(initials: k.giverInitials, size: size)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}
