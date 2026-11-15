import SwiftUI

struct ProfileCommunitySection: View {
    let authorID: UUID?
    let authorName: String
    @StateObject private var store = CommunityStore()
    @ScaledMetric(relativeTo: .headline) private var ownHeadingSize = 17.0
    @ScaledMetric(relativeTo: .title3) private var publicHeadingSize = 21.0

    var body: some View {
        Group {
            if authorID == nil {
                content
                    .padding(18)
                    .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.large))
            } else {
                content
            }
        }
        .task(id: authorID) { await store.refreshAuthoredPosts(authorID: authorID) }
    }

    private var content: some View {
        let posts = CommunityFeedFilters(order: .latest).results(from: store.posts, learning: [])
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    heading.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    seeAll.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    heading
                    seeAll
                }
            }

            if store.feedError {
                HStack {
                    Text("Couldn’t load posts.").font(Theme.Typography.callout)
                    Button("Retry") { Task { await store.refreshAuthoredPosts(authorID: authorID) } }
                        .frame(minHeight: 44)
                        .disabled(store.loading)
                }
            } else if !store.loaded {
                ProgressView().accessibilityLabel("Loading Community posts")
            } else if posts.isEmpty {
                Text("No published posts yet.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
            }

            ForEach(posts.prefix(3)) { post in
                ProfilePostLink(post: post, store: store, showsSkillChips: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
    }

    private var heading: some View {
        HStack(spacing: 8) {
            if authorID == nil {
                Image(systemName: "doc.text").font(.system(size: 14))
                    .accessibilityHidden(true)
            }
            Text("Community & Work")
                .font(.system(size: authorID == nil ? ownHeadingSize : publicHeadingSize, weight: .bold))
                .tracking(authorID == nil ? 0 : -0.4)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder private var seeAll: some View {
        if !store.posts.isEmpty {
            NavigationLink {
                AuthoredCommunityPostsView(authorID: authorID, authorName: authorName, store: store)
            } label: {
                Text("See All").font(Theme.Typography.callout.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ProfilePostPressStyle())
            .accessibilityLabel("See all Community and Work posts")
        }
    }
}

private struct AuthoredCommunityPostsView: View {
    let authorID: UUID?
    let authorName: String
    @ObservedObject var store: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CommunityPostType?

    var body: some View {
        let results = CommunityFeedFilters(order: .latest, kind: kind).results(from: store.posts, learning: [])
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: authorID == nil ? "Your posts" : "\(authorName)’s posts", dismiss: dismiss)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        filter("All", value: nil)
                        ForEach(CommunityPostType.allCases) { value in
                            filter(value.label, value: value)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if store.feedError {
                    Text("Couldn’t refresh posts.").font(Theme.Typography.callout)
                    Button("Retry") { Task { await store.refreshAuthoredPosts(authorID: authorID) } }
                        .frame(minHeight: 44)
                        .disabled(store.loading)
                } else if !store.loaded {
                    ProgressView().accessibilityLabel("Loading posts")
                } else if results.isEmpty {
                    Text(kind == nil ? "No published posts yet." : "No posts of this type.")
                        .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                }

                LazyVStack(spacing: 12) {
                    ForEach(results) { post in
                        ProfilePostLink(post: post, store: store)
                    }
                }
            }
            .padding(Theme.Spacing.screenH)
        }
        .skillSwapScreen()
        .tint(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .refreshable { await store.refreshAuthoredPosts(authorID: authorID) }
    }

    private func filter(_ title: String, value: CommunityPostType?) -> some View {
        let selected = kind == value
        return Button { kind = value } label: {
            Text(title)
                .font(Theme.Typography.callout.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(selected ? Theme.neutralSurface : Theme.surface, in: Capsule())
        }
        .buttonStyle(ProfilePostPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ProfilePostLink: View {
    let post: CommunityPostItem
    @ObservedObject var store: CommunityStore
    var showsSkillChips = false

    var body: some View {
        NavigationLink {
            PostDetailView(store: store, postID: post.id)
                .task {
                    if post.authorID == store.accountID && store.skills.isEmpty {
                        await store.refreshSkills()
                    }
                }
        } label: {
            CommunityPostCard(post: post, showsSkillChips: showsSkillChips)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ProfilePostPressStyle())
    }
}

private struct ProfilePostPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.62 : 1)
    }
}
