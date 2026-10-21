//
//  CommunityView.swift
//  SkillSwap
//
//  Batch B: full Community feed. Made It / Swap Stories / SkillSnaps, monthly
//  challenge, appreciations, comments, create-post, and interactive skill tags.
//  Content is MOCK/local (CommunityStore). "Teach Me This" opens the real
//  RequestExchangeView. See DATA_SOURCES.md.
//

import SwiftUI

struct CommunityView: View {

    @StateObject private var store = CommunityStore()

    @State private var selectedFilter: String = "All"
    @State private var showCreate = false

    private let filters = ["All", "Made It", "Swap Story", "SkillSnap"]

    private var filteredPosts: [CommunityPostItem] {
        selectedFilter == "All"
            ? store.posts
            : store.posts.filter { $0.kind.rawValue == selectedFilter }
    }

    var body: some View {

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {

                    header
                    createBar
                    monthlyChallengeCard
                    filterBar
                    feed
                }
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .skillSwapScreen()
        .sheet(isPresented: $showCreate) {
            CreatePostView(store: store)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("COMMUNITY")
                    .font(.system(size: 12, weight: .heavy)).tracking(2.5)
                    .foregroundStyle(Theme.ink)
                Image(systemName: "sparkle").foregroundStyle(Theme.accent)
            }
            Text("Where skills\nmeet people.")
                .font(.system(size: 40, weight: .black)).tracking(-1.5)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Celebrate what you’ve made and learned together.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenH)
    }

    // MARK: - Create Bar

    private var createBar: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 12) {
                AvatarBadge(initials: CommunityMe.initials, size: 44)
                Text("Share a project, story, or SkillSnap…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.screenH)
    }

    // MARK: - Monthly Challenge

    private var monthlyChallengeCard: some View {
        let challenge = MockData.currentChallenge
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.lavenderSoft)
            Circle().fill(.white.opacity(0.25)).frame(width: 150, height: 150).offset(x: 55, y: -55)
            Image(systemName: "flag.checkered")
                .font(.system(size: 40)).foregroundStyle(.white.opacity(0.6))
                .rotationEffect(.degrees(-10)).offset(x: -22, y: 28)

            VStack(alignment: .leading, spacing: 12) {
                Text("\(challenge.month.uppercased()) SKILL CHALLENGE")
                    .font(.system(size: 10, weight: .heavy)).tracking(2)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                Text(challenge.title)
                    .font(.system(size: 24, weight: .black)).tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(challenge.detail)
                    .font(.system(size: 13)).foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.snappy) { store.joinedChallenge.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: store.joinedChallenge ? "checkmark" : "flag.fill")
                            .font(.system(size: 12))
                        Text(store.joinedChallenge ? "Joined" : "Join Challenge")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(store.joinedChallenge ? .white : Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(store.joinedChallenge ? Theme.ink : .white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenH)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(filters, id: \.self) { f in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = f }
                    } label: {
                        Text(f)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedFilter == f ? .white : Theme.ink)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(selectedFilter == f ? Theme.ink : .white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenH)
        }
    }

    // MARK: - Feed

    private var feed: some View {
        VStack(spacing: 16) {
            if filteredPosts.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack.3d.up.slash",
                    title: "Nothing here yet",
                    message: "Be the first to share in \(selectedFilter).",
                    actionTitle: "Create a Post",
                    action: { showCreate = true }
                )
                .padding(.horizontal, Theme.Spacing.screenH)
            } else {
                ForEach(filteredPosts) { post in
                    PostCard(store: store, post: post)
                        .padding(.horizontal, Theme.Spacing.screenH)
                }
            }
        }
    }
}

// MARK: - Post Card

private struct PostCard: View {

    @ObservedObject var store: CommunityStore
    let post: CommunityPostItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Tapping the content area opens the detail.
            NavigationLink {
                PostDetailView(store: store, postID: post.id)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        AvatarBadge(initials: post.authorInitials, colors: post.bannerColors, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: post.kind.symbol).font(.system(size: 10))
                                Text(post.kind.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                            }
                            .foregroundStyle(Theme.accent)
                            Text(post.authorName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                    }

                    Text(post.title)
                        .font(.system(size: 18, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(post.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !post.skillTags.isEmpty {
                        HStack(spacing: 7) {
                            ForEach(post.skillTags.prefix(3), id: \.self) { tag in
                                SkillPill(text: tag)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 14)

            // Engagement row sits OUTSIDE the link so the heart is independently tappable.
            HStack(spacing: 22) {
                Button {
                    withAnimation(.snappy) { store.toggleAppreciation(post.id) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                            .foregroundStyle(post.likedByMe ? Theme.softPink : .secondary)
                        Text("\(post.appreciations)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    Image(systemName: "bubble.left").foregroundStyle(.secondary)
                    Text("\(post.comments.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }

                Spacer()

                NavigationLink {
                    PostDetailView(store: store, postID: post.id)
                } label: {
                    HStack(spacing: 5) {
                        Text("Open").font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

// MARK: - Preview

#Preview {
    CommunityView()
}
