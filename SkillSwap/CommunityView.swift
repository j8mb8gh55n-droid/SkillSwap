import SwiftUI

struct CommunityView: View {
    @StateObject private var store: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var filters = CommunityFeedFilters()
    @State private var showCreate = false
    @FocusState private var searchFocused: Bool

    private var canCreate: Bool { store.loaded && !store.loading && !store.writing }
    private let createButtonSize: CGFloat = 54
    private let createButtonInset: CGFloat = 16

    init(store: CommunityStore? = nil) {
        _store = StateObject(wrappedValue: store ?? CommunityStore())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                searchField
                filterBar
                feed
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .safeAreaPadding(.bottom, searchFocused ? 0 : createButtonSize + createButtonInset)
        .overlay(alignment: .bottomTrailing) {
            if !searchFocused {
                createButton
                    .padding(.trailing, Theme.Spacing.screenH)
                    .padding(.bottom, createButtonInset)
            }
        }
        .skillSwapScreen()
        .tint(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await store.loadIfNeeded() }
        .navigationDestination(isPresented: $showCreate) {
            CreatePostView(store: store, isPushed: true)
                .navigationBarBackButtonHidden()
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
    }

    private var header: some View {
        Text("Community")
            .font(.headline)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 52)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(alignment: .leading) {
                Button { dismiss() } label: {
                    BackChevron()
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Back")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.mutedStone)
                .accessibilityHidden(true)
            TextField("Search posts or skills", text: $filters.search,
                      prompt: Text("Search posts or skills").foregroundStyle(Theme.mutedStone))
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .frame(minHeight: 44)
            if !filters.search.isEmpty {
                Button { filters.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.mutedStone)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.hairline)
            .allowsHitTesting(false))
    }

    private var createButton: some View {
        Button {
            guard canCreate, !showCreate else { return }
            showCreate = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: createButtonSize, height: createButtonSize)
                .glassEffect(.regular.tint(Theme.lavenderSoft.opacity(0.28)).interactive(), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create Post")
        .disabled(!canCreate || showCreate)
        .opacity(canCreate ? 1 : 0.55)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Feed order", selection: $filters.order) {
                ForEach(CommunityFeedFilters.Order.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Picker("Post type", selection: $filters.kind) {
                        Text("All types").tag(nil as CommunityPostType?)
                        ForEach(CommunityPostType.allCases) { kind in
                            Text(kind.label).tag(Optional(kind))
                        }
                    }
                    .frame(minHeight: 44)
                    Picker("Skill", selection: $filters.skillID) {
                        Text("All skills").tag(nil as Int?)
                        ForEach(store.skills) { skill in Text(skill.name).tag(Optional(skill.id)) }
                    }
                    .frame(minHeight: 44)
                    .disabled(store.skills.isEmpty)
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
                    .font(Theme.Typography.headline)
                feedAction("Retry") { Task { await store.refresh() } }
                    .disabled(store.loading)
            }
        }
        if store.learningError && filters.order == .forYou {
            Text("Couldn’t load your learning skills. Showing the latest posts first.")
                .font(Theme.Typography.meta).foregroundStyle(.secondary)
        }
        if store.skillError {
            Button("Retry loading skill filters") { Task { await store.refreshSkills() } }
        }
        let posts = filters.results(from: store.posts, learning: store.learning)
        if !posts.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    NavigationLink {
                        PostDetailView(store: store, postID: post.id)
                    } label: {
                        CommunityPostCard(post: post, inFeed: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if !store.feedError {
            if !store.loaded || store.loading {
                ProgressView("Loading posts")
            } else if store.posts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Community posts yet.").font(Theme.Typography.headline)
                    Text("Share a question, resource, project, or tip.").foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No posts match your filters.").font(Theme.Typography.headline)
                    feedAction("Clear Filters") {
                        filters = CommunityFeedFilters(order: filters.order)
                    }
                }
            }
        }
    }

    private func feedAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

struct CommunityPostCard: View {
    let post: CommunityPostItem
    var previewLines = 2
    var showsSkillChips = false
    var inFeed = false

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
                .font(inFeed ? Theme.Typography.meta.weight(.semibold) : Theme.Typography.meta)
                Text(post.title).font(Theme.Typography.headline)
                    .fixedSize(horizontal: false, vertical: inFeed)
                Text(post.body).font(Theme.Typography.callout).lineLimit(previewLines)
                    .foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: inFeed)
                Text(post.author.name)
                    .font(inFeed ? Theme.Typography.callout.weight(.medium) : Theme.Typography.meta)
                    .foregroundStyle(inFeed ? Theme.ink : Theme.mutedStone)
                if inFeed && !post.skills.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 6, alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(post.skills) { skill in
                            Text(skill.name)
                                .font(Theme.Typography.meta)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.neutralSurface, in: Capsule())
                        }
                    }
                } else if showsSkillChips && !post.skills.isEmpty {
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
