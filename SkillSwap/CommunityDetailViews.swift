//
//  CommunityDetailViews.swift
//  SkillSwap
//
//  Batch B: Post detail (appreciations + comments + "Teach Me This"), the
//  Create Post interface, and the interactive skill-tag sheet ("The Skill
//  Behind It"). All local/mock; "Teach Me This" navigates to the REAL
//  RequestExchangeView screen. See DATA_SOURCES.md.
//

import SwiftUI

// MARK: - Skill selection wrapper

struct SkillSelection: Identifiable {
    let id: String
    var skill: String { id }
}

// MARK: - Post Detail

struct PostDetailView: View {

    @ObservedObject var store: CommunityStore
    let postID: String

    @Environment(\.dismiss) private var dismiss

    @State private var newComment = ""
    @State private var selectedSkill: SkillSelection?
    @FocusState private var commentFocused: Bool

    private var post: CommunityPostItem? { store.post(postID) }

    var body: some View {

        Group {
            if let post {
                content(post)
            } else {
                EmptyStateView(
                    systemImage: "bubble.left",
                    title: "Post unavailable",
                    message: "This post is no longer available."
                )
                .padding(Theme.Spacing.screenH)
            }
        }
        .skillSwapScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedSkill) { sel in
            SkillTagSheet(skill: sel.skill)
        }
    }

    private func content(_ post: CommunityPostItem) -> some View {

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {

                backButton

                banner(post)

                Text(post.body)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)

                skillTags(post)

                engagementRow(post)

                commentsSection(post)

                teachMeThis(post)
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func banner(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AvatarBadge(initials: post.authorInitials, colors: post.bannerColors, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: post.kind.symbol).font(.system(size: 10))
                        Text(post.kind.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    }
                    .foregroundStyle(Theme.accent)
                    Text(post.authorName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }

            Text(post.title)
                .font(.system(size: 28, weight: .black))
                .tracking(-1)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func skillTags(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE SKILL BEHIND IT")
                .font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundStyle(.secondary)

            FlowTags(tags: post.skillTags) { tag in
                selectedSkill = SkillSelection(id: tag)
            }

            Text("Tap a skill to see who can teach it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func engagementRow(_ post: CommunityPostItem) -> some View {
        HStack(spacing: 22) {
            Button {
                withAnimation(.snappy) { store.toggleAppreciation(post.id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                        .foregroundStyle(post.likedByMe ? Theme.softPink : .secondary)
                    Text("\(post.appreciations)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                Image(systemName: "bubble.left").foregroundStyle(.secondary)
                Text("\(post.comments.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func commentsSection(_ post: CommunityPostItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Appreciations & Comments")

            ForEach(post.comments) { c in
                HStack(alignment: .top, spacing: 12) {
                    AvatarBadge(initials: c.authorInitials, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(c.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }

            if post.comments.isEmpty {
                Text("Be the first to leave an appreciation.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Add an appreciation…", text: $newComment)
                    .font(.system(size: 14))
                    .focused($commentFocused)
                    .submitLabel(.send)
                    .onSubmit(sendComment)

                Button(action: sendComment) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            newComment.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.gray.opacity(0.4) : Theme.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        }
    }

    private func teachMeThis(_ post: CommunityPostItem) -> some View {
        let student = store.student(forAuthor: post.authorName)
        let teaches = post.skillTags.first ?? (student?.teaches.first ?? "a skill")
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                RequestExchangeView(
                    studentName: post.authorName,
                    studentMajor: student?.major ?? "SkillSwap Student",
                    studentTeaches: teaches,
                    studentWantsToLearn: student?.learns.first ?? "",
                    studentInitials: post.authorInitials,
                    bannerColors: post.bannerColors
                )
            } label: {
                HStack {
                    Text("Teach Me This")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(.white)
                .padding(19)
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
            }
            .buttonStyle(.plain)

            SubtleNote(text: "Community posts are a preview. Sending a request opens the real exchange flow.")
        }
    }

    private func sendComment() {
        store.addComment(newComment, to: postID)
        newComment = ""
        commentFocused = false
    }
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

// MARK: - Create Post

struct CreatePostView: View {

    @ObservedObject var store: CommunityStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CommunityPostKind = .madeIt
    @State private var title = ""
    @State private var body_ = ""
    @State private var tagsText = ""

    private let kinds: [CommunityPostKind] = [.madeIt, .swapStory, .skillSnap]

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SHARE WITH THE COMMUNITY")
                            .font(.system(size: 11, weight: .heavy)).tracking(2)
                            .foregroundStyle(Theme.accent)
                        Text("Create a post")
                            .font(.system(size: 30, weight: .black))
                            .tracking(-1)
                            .foregroundStyle(Theme.ink)
                    }

                    // Kind picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TYPE").font(.system(size: 11, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 9) {
                            ForEach(kinds, id: \.rawValue) { k in
                                Button { kind = k } label: {
                                    Text(k.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(kind == k ? .white : Theme.ink)
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(kind == k ? Theme.ink : .white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    field(title: "TITLE", placeholder: "What did you make or learn?", text: $title)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("DETAILS").font(.system(size: 11, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            if body_.isEmpty {
                                Text("Tell the story…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.gray.opacity(0.7))
                                    .padding(.horizontal, 17).padding(.top, 19)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $body_)
                                .font(.system(size: 14))
                                .scrollContentBackground(.hidden)
                                .frame(height: 110)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    }

                    field(title: "SKILL TAGS", placeholder: "Swift, UI/UX Design", text: $tagsText)
                    Text("Separate skills with commas.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)

                    PrimaryButton(title: "Share Post", systemImage: "paperplane.fill", isEnabled: canPost) {
                        store.addPost(
                            kind: kind,
                            title: title,
                            body: body_,
                            tags: tagsText.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        )
                        dismiss()
                    }

                    SubtleNote(text: "Your post appears in the feed for this session. Community posting isn’t saved to the server yet.")
                }
                .padding(Theme.Spacing.screenH)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.creamWarm.ignoresSafeArea())
            .environment(\.colorScheme, .light)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
    }
}

// MARK: - Flow Tags (simple wrapping tag row of buttons)

struct FlowTags: View {
    let tags: [String]
    var onTap: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100), spacing: 9, alignment: .leading)],
            alignment: .leading, spacing: 9
        ) {
            ForEach(tags, id: \.self) { tag in
                Button { onTap(tag) } label: {
                    HStack(spacing: 5) {
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 9))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Theme.lavenderTint)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
