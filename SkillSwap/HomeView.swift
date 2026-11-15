import SwiftUI

struct HomeView: View {
    @Environment(\.colorScheme) private var appearance
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var directory: StudentDirectory
    @StateObject private var community = CommunityStore()

    @State private var unreadNotifications = 0
    private let notifications = NotificationService()
    private var coolAccent: Color {
        appearance == .dark ? Theme.powderBlue : Color(red: 0.29, green: 0.34, blue: 0.49)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground(tone: .lavender, enabled: true)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Theme.powderBlue.opacity(appearance == .dark ? 0.035 : 0.13), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 260)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        recommendedStudents
                        HomeSkillsInDemand()
                        communityPreview
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
                .safeAreaPadding(.bottom, 16)
                .scrollIndicators(.hidden)
                .refreshable {
                    async let roster: Void = directory.refresh()
                    async let posts: Void = community.refresh()
                    _ = await (roster, posts)
                    await refreshNotifications()
                }
            }
            .tint(Theme.ink)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await directory.loadIfNeeded() }
        .task { await community.loadIfNeeded() }
        .onAppear { Task { await refreshNotifications() } }
        .onChange(of: router.tab) { _, tab in
            if tab == .home { Task { await community.refresh() } }
        }
    }

    private func refreshNotifications() async {
        if let count = try? await notifications.unreadCount() {
            unreadNotifications = count
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("SkillSwap")
                .font(Theme.Typography.displayLarge)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            NavigationLink {
                NotificationsView {
                    Task { await refreshNotifications() }
                }
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 17))
                    .foregroundStyle(coolAccent)
                    .frame(width: 44, height: 44)
                    .glassEffect(.clear.tint(Theme.powderBlue.opacity(0.18)), in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if unreadNotifications > 0 {
                            Circle().fill(coolAccent)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unreadNotifications > 0 ? "Notifications, \(unreadNotifications) unread" : "Notifications")
        }
    }

    private var recommendedStudents: some View {
        let students = directory.students.filter { !$0.teaches.isEmpty || !$0.learns.isEmpty }
        let matches = Dictionary(students.compactMap { student in
            community.matchSkills.map { (student.id, $0.match(student)) }
        }, uniquingKeysWith: { first, _ in first })
        let recommended = ExploreSkillMatch.ranked(students, matches: matches).prefix(6)

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recommended Students") {
                Button("Explore All") { router.openExplore() }
                    .buttonStyle(.plain)
            }
            if directory.isLoading || (!directory.hasLoaded && directory.loadError == nil) {
                ProgressView().accessibilityLabel("Loading students")
            } else if let error = directory.loadError {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(Theme.Typography.callout)
                        Button("Try Again") { Task { await directory.refresh() } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if recommended.isEmpty {
                Text("No students to recommend yet.")
                    .font(Theme.Typography.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(recommended)) { student in
                            NavigationLink {
                                StudentProfileView(student: student)
                                    .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                HomeRecommendationCard(student: student,
                                                       isMutual: matches[student.id]?.isMutual == true)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                BookmarkButton(studentID: student.id, minimumTarget: 44).padding(6)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var communityPreview: some View {
        let previews = CommunityFeedFilters().results(from: community.posts, learning: community.learning).prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Community for You") {
                NavigationLink("See All") { CommunityView(store: community) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all Community posts")
            }

            if community.feedError {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(community.loaded ? "Couldn’t refresh Community posts." : "Couldn’t load Community posts.")
                            .font(Theme.Typography.callout)
                        Button("Try Again") { Task { await community.refresh() } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !community.loaded && !community.feedError {
                ProgressView().accessibilityLabel("Loading Community posts")
            } else if community.loaded && previews.isEmpty && !community.feedError {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start the conversation").font(Theme.Typography.headline)
                        Text("Ask a question or share something you’ve learned.")
                            .font(Theme.Typography.callout).foregroundStyle(.secondary)
                        NavigationLink("Open Community") { CommunityView(store: community) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(previews)) { post in
                    NavigationLink {
                        PostDetailView(store: community, postID: post.id)
                    } label: {
                        CommunityPostCard(post: post, previewLines: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle<Trailing: View>(
        _ title: String, @ViewBuilder action: () -> Trailing
    ) -> some View {
        let trailing = action().font(Theme.Typography.callout.weight(.semibold))
            .foregroundStyle(coolAccent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                trailing.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                trailing
            }
        }
        .font(Theme.Typography.title)
        .foregroundStyle(Theme.ink)
    }
}
