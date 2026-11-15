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
    @ObservedObject var store: CommunityStore
    let postID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var editPost: CommunityPostItem?
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Post", dismiss: dismiss)
                if let error {
                    Text(error).font(Theme.Typography.callout).foregroundStyle(.secondary)
                }
                if store.feedError {
                    Button("Retry loading post") { Task { await reload() } }
                }
                if let post = store.post(id: postID) {
                    content(post)
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
        .refreshable { await reload() }
        .sheet(item: $editPost) { post in
            CreatePostView(store: store, post: post)
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

    private func reload() async {
        error = nil
        do { try await store.revalidate(id: postID) }
        catch { if !Task.isCancelled { self.error = "Couldn’t refresh this post." } }
    }

    private func content(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(post.kind.label, systemImage: post.kind.symbol)
                        .font(Theme.Typography.meta).foregroundStyle(Theme.ink)
                    Text(post.title).font(Theme.Typography.displayLarge)
                    Text(post.author.name).font(Theme.Typography.headline)
                    Text(post.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.meta).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(post.body).font(Theme.Typography.callout).textSelection(.enabled)
            Text(post.skills.map(\.name).joined(separator: " · "))
                .font(Theme.Typography.meta).foregroundStyle(Theme.ink)
            if let value = post.externalURL, let url = CommunityPostDraft.httpsURL(value) {
                Link(destination: url) {
                    Label("Open link on \(url.host ?? "the web")", systemImage: "arrow.up.right")
                }
            }
            HStack {
                Button {
                    error = nil
                    Task {
                        do { try await store.setSaved(!post.isSaved, id: post.id) }
                        catch { self.error = "Couldn’t update your saved posts. Try again." }
                    }
                } label: {
                    Label(post.isSaved ? "Unsave" : "Save", systemImage: post.isSaved ? "bookmark.fill" : "bookmark")
                }
                if post.authorID == store.accountID {
                    Spacer()
                    Menu {
                        Button("Edit", systemImage: "pencil") { editPost = post }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Post actions")
                }
            }
            .disabled(store.writing || store.loading)
            if store.writing { ProgressView().accessibilityLabel("Updating post") }
        }
        .foregroundStyle(Theme.ink)
    }
}

struct CreatePostView: View {
    @ObservedObject var store: CommunityStore
    private let postID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CommunityPostDraft
    @State private var error: String?
    @State private var skillSearch = ""

    init(store: CommunityStore, post: CommunityPostItem? = nil) {
        self.store = store
        postID = post?.id
        _draft = State(initialValue: CommunityPostDraft(post: post))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Post") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(CommunityPostType.allCases) { kind in Text(kind.label).tag(kind) }
                    }
                    TextField("Title", text: $draft.title)
                    TextField("Post text", text: $draft.body, axis: .vertical).lineLimit(4...10)
                    TextField("Optional HTTPS link", text: $draft.link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextField("Find a skill", text: $skillSearch)
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
                    if let error { Text(error).foregroundStyle(.red) }
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
            .tint(Theme.ink)
        }
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
