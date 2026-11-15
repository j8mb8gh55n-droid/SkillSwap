//
//  ExploreView.swift
//  SkillSwap
//
//  Explore — skill discovery, redesigned to match the approved Home visual
//  system (SF Pro, soft pastel gradients, lavender atmosphere, reused student
//  cards). Discovery and featured skills use the authenticated Supabase catalog.
//

import SwiftUI

struct ExploreView: View {

    // MARK: - State

    @State private var filters = ExploreFilters()
    @State private var showFilters = false
    @State private var catalog: [CatalogSkill]?
    @State private var isLoadingCatalog = false
    @State private var catalogLoadFailed = false

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var directory: StudentDirectory

    @StateObject private var matchStore = ExploreMatchStore(fetch: ProfileService().fetchMyExploreSkills)
    @State private var matchDetails: MatchDetails?

    private struct MatchDetails: Identifiable {
        let id: String
        let name: String
        let match: ExploreSkillMatch
    }

    private let categories = ["All", "Technology", "Design", "Academics", "Languages", "Creative"]

    // MARK: - Data (real students + featured skill tiles)

    private let discoveryService = StudentDiscoveryService()

    // MARK: - Filtering

    private var discoverableStudents: [DiscoveredStudent] {
        directory.students.filter { !$0.teaches.isEmpty || !$0.learns.isEmpty }
    }

    private var studentMatches: [String: ExploreSkillMatch] {
        guard let skills = matchStore.skills else { return [:] }
        return Dictionary(directory.students.map { ($0.id, skills.match($0)) },
                          uniquingKeysWith: { first, _ in first })
    }

    private var experienceChoices: [SkillExperienceLevel] {
        let stored = Set(directory.students.flatMap { $0.teachingExperienceBySkillID.values })
        return SkillExperienceLevel.allCases.filter { stored.contains($0.rawValue) || filters.experience == $0 }
    }

    // MARK: - Body

    var body: some View {
        let matches = studentMatches
        let eligible = filters.eligibleStudents(in: discoverableStudents, matches: matches)
        let featured = filters.matchingCatalogSkills(in: catalog ?? [], students: eligible)
        let results = filters.matchingStudents(in: eligible)
        return NavigationStack {
            ZStack {
                AtmosphericBackground(tone: .lavender)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        searchSection
                        categorySection
                        featuredSkillsSection(featured)
                        studentsSection(results, matches: matches)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .safeAreaPadding(.bottom, 16)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    async let students: Void = directory.refresh()
                    async let skills: Void = loadCatalog()
                    async let mySkills: Void = matchStore.refresh()
                    _ = await (students, skills, mySkills)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CatalogSkill.self) { skill in
                FeaturedSkillDetailView(skill: skill, filters: filters, matchSkills: matchStore.skills)
            }
        }
        .task { await matchStore.loadIfNeeded() }
        .task { await directory.loadIfNeeded() }
        .task { if catalog == nil { await loadCatalog() } }
        .onAppear { applyPendingCategory() }
        .onChange(of: router.exploreCategory) { _, _ in applyPendingCategory() }
        .onChange(of: directory.isLoading) { _, isLoading in
            if isLoading { matchDetails = nil }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $matchDetails) { details in
            matchDetailsSheet(details)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Explore")
                    .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
                Text("Find skills and students to swap with.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Applies a category deep-linked from Home (if any), then clears it so it
    /// doesn't re-apply when the user later changes the filter manually.
    private func applyPendingCategory() {
        guard let category = router.exploreCategory else { return }
        if categories.contains(category) {
            withAnimation(Theme.Motion.standard) { filters.category = category }
        }
        router.exploreCategory = nil
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Theme.mutedStone)
                TextField("Search skills or students", text: $filters.keyword)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                if !filters.keyword.isEmpty {
                    Button { filters.keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()

            Button { showFilters = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.ink)
                    .frame(width: 52, height: 52)
                    .glassEffect(.clear.tint(Theme.powderBlue.opacity(0.14)), in: .rect(cornerRadius: Theme.Radius.large))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open filters")
            .accessibilityValue(filters.isActive ? "Filters applied" : "")
        }
    }

    // MARK: - Categories

    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(categories, id: \.self) { category in
                    let selected = filters.category == category
                    Button {
                        withAnimation(Theme.Motion.standard) { filters.category = category }
                    } label: {
                        Text(category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.ink : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .background(selected ? Theme.charcoal.opacity(0.12) : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline).allowsHitTesting(false))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Featured Skills

    private func loadCatalog() async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogLoadFailed = false
        defer { isLoadingCatalog = false }
        do {
            let skills = try await discoveryService.fetchCatalog()
            try Task.checkCancellation()
            catalog = skills
        } catch {
            catalogLoadFailed = !Task.isCancelled
        }
    }

    @ViewBuilder
    private func featuredSkillsSection(_ skills: [CatalogSkill]) -> some View {
        if !skills.isEmpty || catalogLoadFailed || catalog == nil || catalog?.isEmpty == true {
            featuredSkillsContent(skills)
        }
    }

    private func featuredSkillsContent(_ skills: [CatalogSkill]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(title: "Featured Skills")

            if catalogLoadFailed {
                messageState(
                    title: catalog == nil ? "Couldn't load featured skills" : "Couldn't refresh featured skills",
                    message: catalog == nil ? "Check your connection and try again." : "Showing the last loaded skills.",
                    retry: { await loadCatalog() }
                )
            } else if catalog == nil {
                loadingState
            } else if catalog?.isEmpty == true {
                messageState(title: "No featured skills yet", message: "The skill catalog is empty.")
            }

            if !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                            NavigationLink(value: skill) {
                                skillCard(skill, colors: HomeGradients.pair(index))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2).padding(.bottom, 4)
                }
            }
        }
    }

    private func skillCard(_ skill: CatalogSkill, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.category.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(Theme.onPastel.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: skillSymbol(skill.category))
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.onPastel.opacity(0.38))
                .frame(maxWidth: .infinity, minHeight: 66)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(skill.name)
                .font(.headline)
                .foregroundStyle(Theme.onPastel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 152)
        .frame(minHeight: 180, alignment: .topLeading)
        .background(richSkillGradient(colors))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .softCardShadow()
    }

    private func richSkillGradient(_ colors: [Color]) -> LinearGradient {
        let a = colors[0]
        let b = colors.count > 1 ? colors[1] : colors[0]
        return LinearGradient(colors: [a, b, a.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func skillSymbol(_ category: String) -> String {
        switch category {
        case "Technology": return "chevron.left.forwardslash.chevron.right"
        case "Design":     return "paintpalette.fill"
        case "Creative":   return "camera.fill"
        case "Languages":  return "bubble.left.and.bubble.right.fill"
        case "Academics":  return "function"
        default:           return "sparkles"
        }
    }

    // MARK: - Students

    private func studentsSection(
        _ results: [DiscoveredStudent], matches: [String: ExploreSkillMatch]
    ) -> some View {
        let checkingMutual = filters.mutualOnly && matchStore.skills == nil
        let state = ExploreFilters.resultsState(
            hasLoaded: directory.hasLoaded,
            isLoading: directory.isLoading,
            hasError: directory.loadError != nil,
            hasStudents: !discoverableStudents.isEmpty,
            matchCount: results.count
        )

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Students").font(Theme.Typography.title).foregroundStyle(Theme.charcoal)
                if directory.hasLoaded && !directory.isLoading && directory.loadError == nil && !checkingMutual {
                    Text(results.count == 1 ? "1 student" : "\(results.count) students")
                        .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                }
            }

            if let error = directory.loadError {
                messageState(
                    title: "Couldn't load students",
                    message: error,
                    retry: { await directory.refresh() }
                )
            }

            if matchStore.loadFailed {
                messageState(title: "Couldn't check skill matches",
                             message: "Try again to load your teaching and learning skills.",
                             retry: { await matchStore.refresh() })
            }

            if checkingMutual {
                if !matchStore.loadFailed { loadingState }
            } else {
                studentResults(state, students: results, matches: matches)
            }
        }
    }

    @ViewBuilder
    private func studentResults(
        _ state: ExploreFilters.ResultsState, students: [DiscoveredStudent], matches: [String: ExploreSkillMatch]
    ) -> some View {
        switch state {
        case .loading:
            loadingState
        case .unavailable:
            EmptyView()
        case .emptyDirectory:
            messageState(title: "No students to discover yet",
                         message: "Students will appear here after they add skills to their profiles.")
        case .noMatches:
            emptyState
        case .results:
            LazyVStack(spacing: 12) {
                ForEach(ExploreSkillMatch.ranked(students, matches: matches)) { student in
                    resultCard(student, match: matches[student.id])
                }
            }
        }
    }

    private func resultCard(_ student: DiscoveredStudent, match: ExploreSkillMatch?) -> some View {
        let teachingSkill = match?.theyTeach.first ?? student.teaches.first
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                NavigationLink {
                    studentDestination(student).toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        DiscoveryStudentAvatar(student: student)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(student.name).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            if !student.major.isEmpty {
                                Text(student.major).font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if match?.isMutual == true {
                                Text("Mutual Match")
                                    .font(.caption.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .glassEffect(.regular.tint(Theme.mint.opacity(0.27)), in: .capsule)
                            }
                            if let teachingSkill {
                                Text(teachingSkill.name)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Theme.surface, in: Capsule())
                                    .accessibilityLabel("Teaches \(teachingSkill.name)")
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                BookmarkButton(studentID: student.id, minimumTarget: 44)
            }

            if let match, match.hasMultipleSkills {
                Button {
                    matchDetails = MatchDetails(id: student.id, name: student.name, match: match)
                } label: {
                    Text("All matching skills")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(Theme.ink)
                .accessibilityLabel("All matching skills with \(student.name)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .background {
            GeometryReader { bounds in
                StudentCardBackground(imageURL: student.avatarURL,
                                      fallbackColors: [Theme.neutralSurface, Theme.surface])
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.large)
                            .fill(Theme.warmIvory.opacity(0.64))
                    }
            }
            .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).strokeBorder(Theme.hairline)
            .allowsHitTesting(false))
    }

    private func matchDetailsSheet(_ details: MatchDetails) -> some View {
        NavigationStack {
            List {
                if !details.match.theyTeach.isEmpty {
                    Section("They can teach you") {
                        ForEach(details.match.theyTeach) { Text($0.name) }
                    }
                }
                if !details.match.youTeach.isEmpty {
                    Section("You can teach them") {
                        ForEach(details.match.youTeach) { Text($0.name) }
                    }
                }
            }
            .navigationTitle(details.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { matchDetails = nil }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func studentDestination(_ s: DiscoveredStudent) -> StudentProfileView {
        StudentProfileView(student: s)
    }

    private var loadingState: some View {
        HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }
            .padding(.vertical, 40)
    }

    private func messageState(title: String, message: String, retry: (() async -> Void)? = nil) -> some View {
        VStack(spacing: 10) {
            Text(title).font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            if let retry {
                Button { Task { await retry() } } label: {
                    Text("Try Again").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Theme.primaryAction).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(Theme.primaryAction)
            Text(filters.mutualOnly ? "No mutual matches" : "No matches").font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
            Text(filters.mutualOnly
                 ? "A mutual match needs a skill you can teach each other. Try clearing filters or updating your skills."
                 : "Try another search or clear your filters.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            Button {
                clearFilters()
            } label: {
                Text("Clear all filters")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    // MARK: - Filter Sheet

    private func clearFilters() {
        withAnimation(Theme.Motion.standard) { filters.clear() }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Skills") {
                    Picker("Category", selection: $filters.category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Direction", selection: Binding(
                        get: { filters.direction },
                        set: { filters.selectDirection($0) }
                    )) {
                        ForEach(ExploreFilters.Direction.allCases, id: \.self) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }
                    Picker("Teaching experience", selection: $filters.experience) {
                        Text("Any level").tag(nil as SkillExperienceLevel?)
                        ForEach(experienceChoices) { level in
                            Text(level.label).tag(Optional(level))
                        }
                    }
                    .disabled(filters.direction == .learns || experienceChoices.isEmpty)

                    if filters.direction == .learns {
                        Text("Experience applies to skills students teach.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if experienceChoices.isEmpty {
                        Text(directory.hasLoaded ? "No teaching experience levels are listed yet."
                             : "Experience levels appear after students load.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Matching") {
                    Toggle("Mutual Matches Only", isOn: $filters.mutualOnly)
                }

                Section("Availability") {
                    Toggle("Accepting exchange requests only", isOn: $filters.acceptingRequestsOnly)
                }

                Section {
                    Button("Clear all filters", action: clearFilters)
                        .disabled(!filters.isActive)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmIvory)
            .navigationTitle("Explore filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
    }

}

// MARK: - Preview

#Preview {
    ExploreView().environmentObject(AppRouter()).environmentObject(SavedStudentsStore()).environmentObject(StudentDirectory())
}
