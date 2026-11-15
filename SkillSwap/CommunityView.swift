import SwiftUI

struct CommunityView: View {
    @StateObject private var store: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var filters = CommunityFeedFilters()
    @State private var showSearch = false
    @State private var showCreate = false

    init(store: CommunityStore? = nil) {
        _store = StateObject(wrappedValue: store ?? CommunityStore())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header
                filterBar
                feed
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .skillSwapScreen()
        .tint(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await store.loadIfNeeded() }
        .sheet(isPresented: $showCreate) {
            CreatePostView(store: store)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                BackChevron().frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            Text("Community").font(Theme.Typography.displayLarge)
            Spacer()
            Button { showSearch.toggle() } label: {
                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(showSearch ? "Hide search" : "Search posts")
            Button { showCreate = true } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .background(Theme.lavenderSoft, in: Circle())
                    .foregroundStyle(Theme.onPastel)
            }
            .accessibilityLabel("Create post")
            .disabled(store.loading || store.writing || !store.loaded)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSearch {
                TextField("Search titles, text, and skills", text: $filters.search)
                    .textFieldStyle(.roundedBorder)
            } else if !filters.search.isEmpty {
                Button("Clear search: \(filters.search)") { filters.search = "" }
                    .font(Theme.Typography.meta)
            }
            Picker("Feed order", selection: $filters.order) {
                ForEach(CommunityFeedFilters.Order.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Picker("Post type", selection: $filters.kind) {
                        Text("All types").tag(nil as CommunityPostType?)
                        ForEach(CommunityPostType.allCases) { kind in
                            Text(kind.label).tag(Optional(kind))
                        }
                    }
                    Picker("Skill", selection: $filters.skillID) {
                        Text("All skills").tag(nil as Int?)
                        ForEach(store.skills) { skill in Text(skill.name).tag(Optional(skill.id)) }
                    }
                    .disabled(store.skills.isEmpty)
                    Toggle("Saved only", isOn: $filters.savedOnly)
                        .toggleStyle(.button)
                }
                .pickerStyle(.menu)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var feed: some View {
        if store.feedError {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.loaded ? "Couldn’t refresh posts." : "Couldn’t load Community.")
                Button("Try Again") { Task { await store.refresh() } }
            }
        }
        if store.learningError && filters.order == .forYou {
            Text("Couldn’t load your learning skills. Showing the latest posts first.")
                .font(Theme.Typography.meta).foregroundStyle(.secondary)
        }
        if store.skillError {
            Button("Retry loading skill filters") { Task { await store.refreshSkills() } }
        }
        if !store.loaded {
            if !store.feedError { ProgressView().accessibilityLabel("Loading posts") }
        } else {
            let posts = filters.results(from: store.posts, learning: store.learning)
            if posts.isEmpty {
                EmptyStateView(systemImage: "text.bubble", title: "No posts to show",
                               message: "Try clearing your filters or share a post.")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        NavigationLink {
                            PostDetailView(store: store, postID: post.id)
                        } label: {
                            CommunityPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPostItem
    var previewLines = 2
    var showsSkillChips = false

    var body: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(post.kind.label, systemImage: post.kind.symbol)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if post.isSaved {
                        Image(systemName: "bookmark.fill").accessibilityLabel("Saved")
                    }
                }
                .font(Theme.Typography.meta)
                Text(post.title).font(Theme.Typography.headline)
                Text(post.body).font(Theme.Typography.callout).lineLimit(previewLines)
                    .foregroundStyle(.secondary)
                Text(post.author.name).font(Theme.Typography.meta).foregroundStyle(.secondary)
                if showsSkillChips && !post.skills.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(post.skills) { skill in
                                Text(skill.name)
                                    .font(Theme.Typography.meta)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.neutralSurface, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                } else if !post.skills.isEmpty {
                    Text(post.skills.map(\.name).joined(separator: " · "))
                        .font(Theme.Typography.meta).foregroundStyle(Theme.ink).lineLimit(1)
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
