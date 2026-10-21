//
//  ProfileView.swift
//  SkillSwap
//
//  Redesigned "My Profile": a blurred photo header (from the user's own avatar)
//  fading into ivory, a sharp circular avatar, name/major/bio, Edit Profile +
//  a small Settings control. Below: only REAL, Supabase-backed sections —
//  Skills I Can Teach, Skills I Want to Learn, Availability. The previous
//  fabricated stats / kudos / badges / history sections were removed (we must
//  not invent completed-exchange counts or social metrics).
//

import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var savedStudents: SavedStudentsStore
    @EnvironmentObject private var directory: StudentDirectory
    @StateObject private var store = ProfileStore()

    /// Count of VALID saved students (resolvable in the real roster) — matches
    /// exactly what the Saved Students screen shows (stale/mock ids don't count).
    private var savedCount: Int { directory.students.filter { savedStudents.isSaved($0.id) }.count }

    // Verified received-kudos count (Phase D1).
    @State private var kudosCount: Int?
    private let kudosService = ExchangeService()

    @State private var isLoggingOut = false
    @State private var logoutError: String?
    @State private var showStatusDialog = false

    // MARK: - Derived (real profile data)

    private var displayName: String { store.fullName.isEmpty ? "Your Name" : store.fullName }
    private var displayMajor: String { store.major.isEmpty ? "University Student" : store.major }

    private var initials: String {
        let words = store.fullName.split(separator: " ")
        guard !words.isEmpty else { return "?" }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func parseSkills(_ v: String) -> [String] {
        v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var teachingList: [String] { parseSkills(store.teachingSkills) }
    private var learningList: [String] { parseSkills(store.learningSkills) }
    private var availabilityList: [String] { parseSkills(store.availability) }

    private var photoURL: URL? { store.avatarURL.flatMap(URL.init(string:)) }
    private let bannerColors = [Theme.brightLavender, Theme.powderBlue]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmIvory.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profileHeader

                        VStack(alignment: .leading, spacing: 20) {
                            if !store.bio.isEmpty { aboutSection }
                            teachingSection
                            learningSection
                            availabilitySection
                            yourImpactCard
                            savedAndKudos
                            manageSkillsLink
                            logoutButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 44)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.loadIfNeeded() }
            .task { await directory.loadIfNeeded() }
            .task { kudosCount = try? await kudosService.myKudosCount() }
            .alert("Couldn't Load Profile", isPresented: Binding(
                get: { store.loadError != nil }, set: { if !$0 { store.loadError = nil } })) {
                Button("Retry") { Task { await store.load() } }
                Button("OK", role: .cancel) { store.loadError = nil }
            } message: { Text(store.loadError ?? "Please try again.") }
            .alert("Logout Failed", isPresented: Binding(
                get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
                Button("OK", role: .cancel) { logoutError = nil }
            } message: { Text(logoutError ?? "Please try again.") }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        ZStack(alignment: .topLeading) {
            bannerVisual
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Small Settings control, top-right.
            HStack {
                Spacer()
                NavigationLink { SettingsView(store: store) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.charcoal)
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Settings")
            }
            .padding(.horizontal, 20).padding(.top, 60)

            identity
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 20)
        }
        .frame(height: 260)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.charcoal)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(displayMajor)
                    .font(Theme.Typography.callout).foregroundStyle(Theme.charcoal.opacity(0.7))
            }
            HStack(spacing: 10) {
                NavigationLink { EditProfileView(store: store) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil"); Text("Edit Profile")
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.primaryAction).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                statusControl
            }
            .padding(.top, 2)
        }
    }

    // Phase D5 / F3: change whether you're accepting new exchanges (saved
    // instantly). Uses a native confirmationDialog (bottom sheet) instead of a
    // Menu so the picker never overlaps the Edit Profile button or nearby content.
    private var statusControl: some View {
        let status = AvailabilityStatus.from(store.availabilityStatus)
        return Button {
            showStatusDialog = true
        } label: {
            HStack(spacing: 7) {
                Circle().fill(status.tint).frame(width: 9, height: 9)
                Text(status.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.charcoal)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedStone)
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(status.tint.opacity(0.35)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Availability status: \(status.label)")
        .confirmationDialog("Availability", isPresented: $showStatusDialog, titleVisibility: .visible) {
            ForEach(AvailabilityStatus.allCases) { option in
                Button(option == status ? "\(option.label) ✓" : option.label) {
                    Task { await store.setAvailabilityStatus(option) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether you're accepting new exchanges.")
        }
    }

    @ViewBuilder private var bannerVisual: some View {
        let scrim = LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill().scaleEffect(1.1).blur(radius: 28).opacity(0.95) }
                else { scrim }
            }
        } else {
            scrim
        }
    }

    @ViewBuilder private var avatar: some View {
        let size: CGFloat = 88
        Group {
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { avatarFallback(size) }
                }
            } else {
                avatarFallback(size)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private func avatarFallback(_ size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if store.fullName.isEmpty {
                Image(systemName: "person.fill").font(.system(size: size * 0.4)).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        section(title: "About", symbol: "person.text.rectangle") {
            Text(store.bio).font(.system(size: 14)).foregroundStyle(Theme.charcoal.opacity(0.8)).lineSpacing(4)
        }
    }

    private var teachingSection: some View {
        section(title: "Skills I Can Teach", symbol: "lightbulb.fill") {
            if teachingList.isEmpty {
                emptyRow("Add the skills you can teach.", "Add Teaching Skills", target: .teach)
            } else {
                teachingSkillTags(teachingList)
            }
        }
    }

    private var learningSection: some View {
        section(title: "Skills I Want to Learn", symbol: "book.closed.fill") {
            if learningList.isEmpty {
                emptyRow("Add skills you're interested in learning.", "Add Learning Skills", target: .learn)
            } else {
                skillTags(learningList, color: Theme.powderBlue.opacity(0.5))
            }
        }
    }

    private var availabilitySection: some View {
        section(title: "Availability", symbol: "calendar") {
            if availabilityList.isEmpty {
                emptyRow("Let others know when you're free.", "Set Availability", target: .availability)
            } else {
                skillTags(availabilityList, color: Theme.mint.opacity(0.5))
            }
        }
    }

    // Phase D2: a single compact nav card (keeps the Profile page uncluttered).
    // Opens the dedicated Stats & Achievements screen, which loads verified data.
    private var yourImpactCard: some View {
        NavigationLink { StatsAchievementsView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill").font(.system(size: 15)).foregroundStyle(Theme.primaryAction).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Impact").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    Text("See your stats, achievements & milestones")
                        .font(.system(size: 12)).foregroundStyle(Theme.mutedStone)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedStone)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    private func section<Content: View>(title: String, symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.primaryAction)
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    private func emptyRow(_ message: String, _ cta: String, target: SkillsSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.mutedStone)
            NavigationLink { SkillsAvailabilityView(store: store, scrollTarget: target) } label: {
                HStack(spacing: 6) { Image(systemName: "plus.circle.fill"); Text(cta) }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction)
            }
            .buttonStyle(.plain)
        }
    }

    /// Teaching tags that also show the verified experience level when one is
    /// set (Phase D4). A skill with no level simply shows its name (graceful).
    private func teachingSkillTags(_ skills: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(skills, id: \.self) { skill in
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    if let level = SkillExperienceLevel.label(forSlug: store.teachingLevels[skill] ?? store.teachingLevels[skill.lowercased()]) {
                        Text(level).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.primaryAction)
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brightLavender.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func skillTags(_ skills: [String], color: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(skills, id: \.self) { skill in
                Text(skill)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color).clipShape(Capsule())
            }
        }
    }

    private var savedAndKudos: some View {
        VStack(spacing: 0) {
            NavigationLink { SavedStudentsView() } label: {
                linkRow(icon: "bookmark", title: "Saved Students",
                        trailing: savedCount > 0 ? "\(savedCount)" : nil)
            }
            .buttonStyle(.plain)
            HairlineDivider().padding(.leading, 50)
            NavigationLink { KudosReceivedView() } label: {
                linkRow(icon: "heart", title: "Kudos", trailing: (kudosCount ?? 0) > 0 ? "\(kudosCount!)" : nil)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    private func linkRow(icon: String, title: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.primaryAction).frame(width: 22)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mutedStone) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedStone)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var manageSkillsLink: some View {
        NavigationLink { SkillsAvailabilityView(store: store) } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundStyle(Theme.primaryAction)
                Text("Manage Skills & Availability").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedStone)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var logoutButton: some View {
        Button {
            Task { await logOut() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 17))
                Text(isLoggingOut ? "Logging Out…" : "Log Out").font(.system(size: 15, weight: .semibold))
                Spacer()
                if isLoggingOut { ProgressView() }
            }
            .foregroundStyle(.red)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoggingOut)
        .padding(.top, 4)
    }

    private func logOut() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }
        do { try await authManager.signOut() }
        catch { logoutError = error.localizedDescription }
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(AppRouter())
        .environmentObject(SavedStudentsStore())
        .environmentObject(StudentDirectory())
}
