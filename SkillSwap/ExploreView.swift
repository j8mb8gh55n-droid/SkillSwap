//
//  ExploreView.swift
//  SkillSwap
//
//  Explore — skill discovery, redesigned to match the approved Home visual
//  system (SF Pro, soft pastel gradients, lavender atmosphere, reused student
//  cards). Students & featured skills come from the shared MockData roster
//  (same source as Home). Mutual-match uses the signed-in user's real skills.
//

import SwiftUI

struct ExploreView: View {

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showFilters = false
    @State private var selectedSkill: SkillSelection?

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var directory: StudentDirectory

    /// Real profile (for mutual-match). Roster is now REAL (Supabase).
    @StateObject private var profile = ProfileStore()

    private var profileInitials: String {
        profile.fullName.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private let categories = ["All", "Technology", "Design", "Academics", "Languages", "Creative"]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    // MARK: - Data (real students + featured skill tiles)

    private var skills: [DemandSkill] { MockData.skillsInDemand }

    // MARK: - Filtering

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredStudents: [DiscoveredStudent] {
        directory.students.filter { s in
            let matchesCategory = selectedCategory == "All" || s.categories.contains(selectedCategory)
            let matchesSearch = query.isEmpty
                || s.name.localizedCaseInsensitiveContains(query)
                || s.major.localizedCaseInsensitiveContains(query)
                || s.teaches.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || s.learns.contains { $0.name.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesSearch
        }
    }

    private var filteredSkills: [DemandSkill] {
        skills.filter { d in
            let matchesCategory = selectedCategory == "All" || d.category == selectedCategory
            let matchesSearch = query.isEmpty
                || d.skill.localizedCaseInsensitiveContains(query)
                || d.category.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }

    // MARK: - Mutual match (real user skills)

    private var myTeaching: [String] { parse(profile.teachingSkills) }
    private var myLearning: [String] { parse(profile.learningSkills) }

    private func parse(_ v: String) -> [String] {
        v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func matchInfo(for s: DiscoveredStudent) -> (label: String, priority: Int)? {
        let teachesWhatIWant = s.teaches.contains { t in
            myLearning.contains { $0.localizedCaseInsensitiveCompare(t.name) == .orderedSame }
        }
        let wantsWhatITeach = s.learns.contains { l in
            myTeaching.contains { $0.localizedCaseInsensitiveCompare(l.name) == .orderedSame }
        }
        if teachesWhatIWant && wantsWhatITeach { return ("Mutual match", 3) }
        if teachesWhatIWant { return ("Teaches what you want", 2) }
        if wantsWhatITeach { return ("Wants what you teach", 1) }
        return nil
    }

    private var rankedStudents: [DiscoveredStudent] {
        filteredStudents.enumerated().sorted { a, b in
            let pa = matchInfo(for: a.element)?.priority ?? 0
            let pb = matchInfo(for: b.element)?.priority ?? 0
            return pa != pb ? pa > pb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground(tone: .lavender)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        searchSection
                        categorySection
                        if !filteredSkills.isEmpty { featuredSkillsSection }
                        studentsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await directory.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await profile.loadIfNeeded() }
        .task { await directory.loadIfNeeded() }
        .onAppear { applyPendingCategory() }
        .onChange(of: router.exploreCategory) { _, _ in applyPendingCategory() }
        .sheet(isPresented: $showFilters) {
            filterSheet.presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedSkill) { sel in SkillTagSheet(skill: sel.skill) }
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
            withAnimation(Theme.Motion.standard) { selectedCategory = category }
        }
        router.exploreCategory = nil
    }

    private var headerAvatar: some View {
        Group {
            if let url = profile.avatarURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { avatarFallback }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                avatarFallback
            }
        }
    }

    @ViewBuilder private var avatarFallback: some View {
        if profileInitials.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: 17)).foregroundStyle(Theme.primaryAction)
                .frame(width: 44, height: 44)
                .background(Theme.brightLavender.opacity(0.35))
                .background(.ultraThinMaterial, in: Circle())
                .clipShape(Circle())
        } else {
            Monogram(initials: profileInitials, size: 44)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Theme.mutedStone)
                TextField("Search skills or students", text: $searchText)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedStone)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()

            Button { showFilters = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.mutedStone)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.large))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open filters")
        }
    }

    // MARK: - Categories

    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(categories, id: \.self) { category in
                    let selected = selectedCategory == category
                    Button {
                        withAnimation(Theme.Motion.standard) { selectedCategory = category }
                    } label: {
                        Text(category)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? Theme.charcoal : Theme.mutedStone)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(selected ? Theme.charcoal.opacity(0.08) : Color.white.opacity(0.9))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Featured Skills

    private var featuredSkillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(title: "Featured Skills")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(filteredSkills.enumerated()), id: \.element.id) { i, d in
                        Button { selectedSkill = SkillSelection(id: d.skill) } label: {
                            skillCard(d, colors: HomeGradients.pair(i))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2).padding(.bottom, 4)
            }
        }
    }

    private func skillCard(_ d: DemandSkill, colors: [Color]) -> some View {
        ZStack {
            richSkillGradient(colors)

            // Category label — toward the top.
            Text(d.category.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(Theme.charcoal.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)

            // Large, elegant translucent illustration — central/upper.
            Image(systemName: skillSymbol(d.category))
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: -8)

            // Skill name — near the bottom; wraps without changing height.
            Text(d.skill)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
                .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(16)
        }
        .frame(width: 152, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(.white.opacity(0.4), lineWidth: 1))
        .softCardShadow()
    }

    /// Slightly richer 3-stop pastel blend for Featured Skills.
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

    private var studentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Students").font(Theme.Typography.title).foregroundStyle(Theme.charcoal)
                    Text("\(filteredStudents.count) to discover")
                        .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                }
                Spacer()
                if selectedCategory != "All" || !searchText.isEmpty {
                    Button("Clear") {
                        withAnimation(Theme.Motion.standard) { searchText = ""; selectedCategory = "All" }
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                }
            }

            if directory.isLoading && directory.students.isEmpty {
                loadingState
            } else if let err = directory.loadError, directory.students.isEmpty {
                messageState(title: "Couldn't load students", message: err, retry: true)
            } else if directory.students.isEmpty {
                messageState(title: "No students yet",
                             message: "Once other students join, they'll appear here.", retry: false)
            } else if filteredStudents.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(rankedStudents) { s in
                        let i = directory.students.firstIndex(where: { $0.id == s.id }) ?? 0
                        NavigationLink { studentDestination(s) } label: {
                            HomeStudentCard(
                                student: s.card(colorIndex: i),
                                colors: HomeGradients.studentPair(i),
                                style: .gem,
                                matchLabel: matchInfo(for: s)?.label
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) { BookmarkButton(studentID: s.id).padding(10) }
                    }
                }
            }
        }
    }

    private func studentDestination(_ s: DiscoveredStudent) -> StudentProfileView {
        StudentProfileView(student: s)
    }

    private var loadingState: some View {
        HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }
            .padding(.vertical, 40)
    }

    private func messageState(title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Text(title).font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            if retry {
                Button { Task { await directory.load() } } label: {
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
            Text("Nothing here just yet").font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
            Text("Try another skill or explore all categories.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(Theme.Motion.standard) { searchText = ""; selectedCategory = "All" }
            } label: {
                Text("Explore everything")
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

    private var filterSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Filter by category").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.charcoal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(categories, id: \.self) { category in
                    let selected = selectedCategory == category
                    Button {
                        selectedCategory = category; showFilters = false
                    } label: {
                        Text(category)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? Theme.charcoal : Theme.mutedStone)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(selected ? Theme.charcoal.opacity(0.08) : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                selectedCategory = "All"; searchText = ""; showFilters = false
            } label: {
                Text("Clear all filters")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Theme.warmIvory)
    }
}

// MARK: - Preview

#Preview {
    ExploreView().environmentObject(AppRouter()).environmentObject(SavedStudentsStore()).environmentObject(StudentDirectory())
}
