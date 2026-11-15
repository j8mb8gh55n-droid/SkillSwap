import SwiftUI

struct SkillSelection: Identifiable {
    let id: String
    var skill: String { id }
}

// MARK: - Skill Tag Sheet ("The Skill Behind It")

struct SkillTagSheet: View {

    let skill: String

    @Environment(\.dismiss) private var dismiss

    /// Mock students who teach this skill ("The Skill Behind It").
    private var teachers: [MockStudent] {
        MockData.students.filter {
            $0.teaches.contains { $0.localizedCaseInsensitiveContains(skill) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("THE SKILL BEHIND IT")
                            .font(.system(size: 11, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                        Text(skill)
                            .font(.system(size: 28, weight: .black))
                            .tracking(-0.8)
                            .foregroundStyle(Theme.ink)
                        Text("Students who can teach this.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    if teachers.isEmpty {
                        EmptyStateView(
                            systemImage: "person.fill.questionmark",
                            title: "No teachers yet",
                            message: "No students currently list \(skill). Explore to discover more."
                        )
                    } else {
                        ForEach(teachers) { student in
                            NavigationLink {
                                RequestExchangeView(
                                    studentName: student.name,
                                    studentMajor: student.major,
                                    studentTeaches: skill,
                                    studentWantsToLearn: student.learns.first ?? "",
                                    studentInitials: student.initials,
                                    bannerColors: student.bannerColors
                                )
                            } label: {
                                teacherRow(student)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.Spacing.screenH)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(Theme.creamWarm.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.colorScheme, .light)
        }
        .presentationDragIndicator(.visible)
    }

    private func teacherRow(_ student: MockStudent) -> some View {
        RoundedCard {
            HStack(spacing: 14) {
                AvatarBadge(initials: student.initials, colors: student.bannerColors, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(student.major)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Teach Me This")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                }
                .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct PostDetailView: View {
    private struct AuthorConnection: Hashable {
        let student: DiscoveredStudent
        let authorID: UUID
        let suggestion: String
    }

    @ObservedObject var store: CommunityStore
    let postID: UUID
    var ancestorPostIDs: Set<UUID> = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var appearance
    @StateObject private var relatedStore = CommunityStore()
    @State private var editPost: CommunityPostItem?
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var authorConnection: AuthorConnection?
    @State private var connectingPostID: UUID?
    @State private var relatedPostID: UUID?

    private var excludedPostIDs: Set<UUID> { ancestorPostIDs.union([postID]) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error {
                    Text(error).font(Theme.Typography.callout).foregroundStyle(Theme.validationText)
                }
                if store.feedError {
                    Button("Retry loading post") { Task { await reload() } }
                }
                if let post = store.post(id: postID) {
                    content(post)
                    recommendations(for: post)
                } else {
                    EmptyStateView(systemImage: "doc", title: "Post unavailable",
                                   message: "It may have been deleted.")
                }
            }
            .padding(Theme.Spacing.screenH)
        }
        .skillSwapScreen()
        .tint(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await reload() }
        .task(id: store.post(id: postID)?.updatedAt) {
            guard !store.hasFullFeed, let post = store.post(id: postID) else { return }
            await relatedStore.loadRelatedPosts(to: post, excluding: excludedPostIDs)
        }
        .task(id: connectingPostID) {
            guard let id = connectingPostID else { return }
            defer {
                if connectingPostID == id { connectingPostID = nil }
            }
            if let post = store.post(id: id) { await connect(to: post) }
        }
        .refreshable { await reload() }
        .navigationDestination(item: $authorConnection) { connection in
            let student = connection.student
            ChatConversationView(
                conversation: ChatConversation(
                    participant: ChatParticipant(id: connection.authorID, name: student.name,
                                                 initials: student.initials, avatarURL: student.avatarURL),
                    state: .introduction
                ),
                introductionSuggestion: connection.suggestion
            )
        }
        .navigationDestination(item: $relatedPostID) { id in
            PostDetailView(store: store.post(id: id) == nil ? relatedStore : store,
                           postID: id, ancestorPostIDs: excludedPostIDs)
        }
        .sheet(item: $editPost) { post in
            CreatePostView(store: store, post: post)
                .task { if store.skills.isEmpty { await store.refreshSkills() } }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await store.delete(id: postID)
                        dismiss()
                    } catch {
                        self.error = "Couldn’t delete the post. Try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        Text("Post")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 52)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(alignment: .leading) {
                Button { dismiss() } label: {
                    BackChevron()
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            .overlay(alignment: .trailing) {
                if let post = store.post(id: postID), post.authorID == store.accountID {
                    Menu {
                        Button("Edit", systemImage: "pencil") { editPost = post }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Post actions")
                    .disabled(store.writing || store.loading)
                }
            }
            .foregroundStyle(Theme.ink)
    }

    private func reload() async {
        error = nil
        do { try await store.revalidate(id: postID) }
        catch { if !Task.isCancelled { self.error = "Couldn’t refresh this post." } }
    }

    private func connect(to post: CommunityPostItem) async {
        guard authorConnection == nil,
              let accountID = store.accountID, accountID != post.authorID else { return }
        error = nil
        do {
            let author = try await StudentDiscoveryService().fetchProfile(id: post.authorID)
            try Task.checkCancellation()
            guard let author else {
                error = "This post’s author is unavailable."
                return
            }
            let title = post.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let suggestion = "Hi! I saw your SkillSwap post “\(title)” and would love to learn more about it."
            authorConnection = AuthorConnection(student: author, authorID: post.authorID, suggestion: suggestion)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = "Couldn’t open the author’s conversation. Try again." }
        }
    }

    private func content(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink {
                    PostAuthorProfileView(authorID: post.authorID, isOwnProfile: post.authorID == store.accountID)
                } label: {
                    authorIdentity(post)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the author’s profile")
                Spacer(minLength: 0)
                Label(post.kind.label, systemImage: post.kind.symbol)
                    .font(Theme.Typography.meta.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Theme.neutralSurface, in: Capsule())
            }
            Text(post.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(post.body)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !post.skills.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(post.skills) { skill in
                        Text(skill.name)
                            .font(Theme.Typography.meta.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(
                                (skill.id.isMultiple(of: 2) ? Theme.mint : Theme.lavenderTint)
                                    .opacity(appearance == .dark ? 0.20 : 0.55),
                                in: Capsule()
                            )
                    }
                }
            }
            if let value = post.externalURL, let url = CommunityPostDraft.httpsURL(value) {
                Link(destination: url) {
                    Label("Open link on \(url.host ?? "the web")", systemImage: "arrow.up.right")
                        .font(Theme.Typography.callout.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            postActions(post)
        }
        .foregroundStyle(Theme.ink)
    }

    private func authorIdentity(_ post: CommunityPostItem) -> some View {
        let initials = String(post.author.name.split(whereSeparator: \.isWhitespace)
            .prefix(2).compactMap(\.first)).uppercased()
        return HStack(spacing: 10) {
            AsyncImage(url: post.author.avatarURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Monogram(initials: initials, size: 44)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.author.name).font(Theme.Typography.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(post.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func postActions(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    error = nil
                    Task {
                        do { try await store.setSaved(!post.isSaved, id: post.id) }
                        catch { self.error = "Couldn’t update your saved posts. Try again." }
                    }
                } label: {
                    Label(post.isSaved ? "Saved" : "Save", systemImage: post.isSaved ? "bookmark.fill" : "bookmark")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(post.isSaved ? "Removes this post from Saved" : "Adds this post to Saved")
                Spacer(minLength: 0)
                if connectingPostID != nil {
                    ProgressView().accessibilityLabel("Opening conversation")
                }
                if let accountID = store.accountID, post.authorID != accountID {
                    Button {
                        connectingPostID = post.id
                    } label: {
                        Label("Connect", systemImage: "message")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .accessibilityHint("Opens a conversation with the post author")
                    .disabled(connectingPostID != nil)
                }
            }
            .padding(.horizontal, 8)
            .disabled(store.writing || store.loading)
            Divider()
            if store.writing { ProgressView().accessibilityLabel("Updating post") }
        }
    }

    @ViewBuilder private func recommendations(for post: CommunityPostItem) -> some View {
        let skillIDs = Set(post.skills.map(\.id))
        let excluded = excludedPostIDs
        var seen = Set<UUID>()
        let candidates = (store.posts + relatedStore.posts).filter {
            !excluded.contains($0.id) && seen.insert($0.id).inserted
        }
        let ranked = candidates.map {
            (post: $0, overlap: skillIDs.intersection($0.skills.map(\.id)).count)
        }.sorted { lhs, rhs in
            if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
            if lhs.post.createdAt != rhs.post.createdAt { return lhs.post.createdAt > rhs.post.createdAt }
            return lhs.post.id.uuidString < rhs.post.id.uuidString
        }
        let posts = ranked.prefix(3).map(\.post)
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("More like this").font(Theme.Typography.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(posts) { candidate in
                    Button {
                        if relatedPostID == nil { relatedPostID = candidate.id }
                    } label: {
                        CommunityPostCard(post: candidate, previewLines: 1, inFeed: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PostAuthorProfileView: View {
    let authorID: UUID
    let isOwnProfile: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var student: DiscoveredStudent?
    @State private var loading = true

    var body: some View {
        Group {
            if let student {
                StudentProfileView(student: student, isOwnPublicProfile: isOwnProfile)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Author", dismiss: dismiss)
                    if loading {
                        ProgressView("Loading profile")
                    } else {
                        Text("This author’s profile couldn’t be loaded.")
                        Button("Retry") { Task { await load() } }.frame(minHeight: 44)
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.screenH)
                .skillSwapScreen()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { if student == nil { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        student = try? await StudentDiscoveryService().fetchProfile(id: authorID, includingCurrentStudent: isOwnProfile)
    }
}

struct CreatePostView: View {
    @ObservedObject var store: CommunityStore
    private let postID: UUID?
    private let isPushed: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CommunityPostDraft
    @State private var error: String?
    @State private var skillSearch = ""

    init(store: CommunityStore, post: CommunityPostItem? = nil, isPushed: Bool = false) {
        self.store = store
        postID = post?.id
        self.isPushed = isPushed
        _draft = State(initialValue: CommunityPostDraft(post: post))
    }

    var body: some View {
        if isPushed {
            form
        } else {
            NavigationStack { form }
        }
    }

    private var form: some View {
        Form {
            Section("Post") {
                Picker("Type", selection: $draft.kind) {
                    ForEach(CommunityPostType.allCases) { kind in Text(kind.label).tag(kind) }
                }
                TextField("Title", text: $draft.title, prompt: Text("Title").foregroundStyle(Theme.mutedStone))
                TextField("Post text", text: $draft.body, prompt: Text("Post text").foregroundStyle(Theme.mutedStone), axis: .vertical).lineLimit(4...10)
                TextField("Optional HTTPS link", text: $draft.link, prompt: Text("Optional HTTPS link").foregroundStyle(Theme.mutedStone))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                TextField("Find a skill", text: $skillSearch, prompt: Text("Find a skill").foregroundStyle(Theme.mutedStone))
                if store.skillError {
                    Button("Retry loading skills") { Task { await store.refreshSkills() } }
                } else if store.skills.isEmpty {
                    Text("No catalog skills available.").foregroundStyle(.secondary)
                }
                ForEach(store.skills.filter { skillSearch.isEmpty || $0.name.localizedStandardContains(skillSearch) }) { skill in
                    Toggle(skill.name, isOn: Binding(
                        get: { draft.skillIDs.contains(skill.id) },
                        set: { selected in
                            if selected { draft.skillIDs.insert(skill.id) }
                            else { draft.skillIDs.remove(skill.id) }
                        }
                    ))
                    .disabled(draft.skillIDs.count >= CommunityPostDraft.tagLimit && !draft.skillIDs.contains(skill.id))
                }
            } header: {
                Text("Skills (\(draft.skillIDs.count) selected)")
            }
            Section {
                Text("Signed-in students can see your posts even when Discoverable in Explore is off.")
                    .font(Theme.Typography.meta).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(postID == nil ? "Create Post" : "Edit Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(store.writing)
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.writing {
                    ProgressView().accessibilityLabel("Saving post")
                } else {
                    Button(postID == nil ? "Publish" : "Save") { submit() }.disabled(store.loading)
                }
            }
        }
        .interactiveDismissDisabled(store.writing)
        .alert("Couldn’t save post", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .tint(Theme.ink)
    }

    private func submit() {
        if let validationError = draft.validationError {
            error = validationError
            return
        }
        error = nil
        Task {
            do {
                try await store.save(draft, id: postID)
                dismiss()
            } catch {
                self.error = "Couldn’t confirm the save. Check the feed before trying to publish again."
            }
        }
    }
}
