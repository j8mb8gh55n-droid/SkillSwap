//
//  HomeView.swift
//  SkillSwap
//
//  Soft Chromatic iOS — refinement pass. SF Pro, soft lavender static
//  atmosphere, continuous-blend cards, compact app-like density. Visual only —
//  no services, models, queries, or navigation architecture changed. Removed:
//  Skill Chemistry, Skill Roulette, promotional hero, Upcoming placeholder,
//  redundant Quick Actions.
//

import SwiftUI

struct HomeView: View {

    // MARK: - Profile (real, for personalization + skill editing)

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var directory: StudentDirectory
    @StateObject private var profile = ProfileStore()

    @State private var unreadNotifications = 0
    private let notifications = NotificationService()

    // MARK: - Derived content

    private var firstName: String {
        profile.fullName.split(separator: " ").first.map(String.init) ?? ""
    }
    private var profileInitials: String {
        profile.fullName.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
    private var timeWord: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
    /// Personalized greeting for the signed-in student; graceful fallback
    /// ("Good morning!") when the name isn't available.
    private var greetingLine: String {
        firstName.isEmpty ? "\(timeWord)!" : "\(timeWord), \(firstName)!"
    }
    private var teachingSkillsList: [String] {
        profile.teachingSkills.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var learningSkillsList: [String] {
        profile.learningSkills.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var hasAnySkills: Bool { !teachingSkillsList.isEmpty || !learningSkillsList.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Static lavender atmosphere (set enabled: false for plain ivory).
                AtmosphericBackground(tone: .lavender, enabled: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        categoriesSection
                        skillSpaceSection
                        CommunitySpotlightSection()
                        featuredStudentsSection
                        HomeSkillsInDemand()
                        HomeHiddenGems()
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        // Reload on appear so the greeting reflects name edits made in Profile,
        // and the unread badge refreshes when returning from NotificationsView.
        .onAppear {
            Task {
                await profile.load()
                unreadNotifications = (try? await notifications.unreadCount()) ?? 0
            }
        }
        .task { await directory.loadIfNeeded() }
    }

    // MARK: - Header (compact, glass shortcuts)

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(greetingLine)
                .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()

            NavigationLink {
                NotificationsView()
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 17)).foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if unreadNotifications > 0 {
                            Circle().fill(Theme.primaryAction)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                .offset(x: -2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unreadNotifications > 0 ? "Notifications, \(unreadNotifications) unread" : "Notifications")
        }
        .padding(.top, 4)
    }

    // MARK: - Explore Skills (bento, name-only)

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(title: "Explore Skills")

            HStack(alignment: .top, spacing: 12) {
                bentoTile("Technology", colors: [Theme.mint, Theme.freshSage, Theme.sage], height: 168)
                VStack(spacing: 12) {
                    bentoTile("Design", colors: [Theme.brightLavender, Theme.lilac, Theme.blush], height: 78)
                    bentoTile("Academics", colors: [Theme.softPeach, Theme.blush, Theme.lilac], height: 78)
                }
            }
            bentoTile("Languages", colors: [Theme.periwinkle, Theme.lilac, Theme.mint], height: 86)
        }
    }

    private func bentoTile(_ title: String, colors: [Color], height: CGFloat) -> some View {
        Button {
            router.openExplore(category: title)
        } label: {
            ZStack(alignment: .bottomLeading) {
                HomeGradients.soft(colors)
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.onPastel)
                    .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(.white.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Your Skill Space (moved up; real skills + edit action)

    private var skillSpaceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(title: "Your Skill Space")

            if hasAnySkills {
                VStack(spacing: 0) {
                    skillSpaceRow(symbol: "lightbulb", label: "I can teach",
                                  value: teachingSkillsList.isEmpty ? "Not set yet" : teachingSkillsList.joined(separator: " · "))
                    HairlineDivider().padding(.vertical, 12)
                    skillSpaceRow(symbol: "book", label: "I want to learn",
                                  value: learningSkillsList.isEmpty ? "Not set yet" : learningSkillsList.joined(separator: " · "))
                }
                .padding(16)
                .background(Theme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
                .softCardShadow()
            } else {
                NavigationLink { EditProfileView(store: profile) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.forestGreen)
                            .frame(width: 44, height: 44)
                            .background(Theme.mint.opacity(0.4)).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your skills").font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
                            Text("Tell others what you teach and want to learn.")
                                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.mutedStone)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
                    .softCardShadow()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func skillSpaceRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Theme.forestGreen).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                Text(value).font(Theme.Typography.headline).foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Featured Students

    @ViewBuilder private var featuredStudentsSection: some View {
        // Discovery section — real students. Hidden while empty/loading so Home
        // never shows an empty header.
        if !directory.students.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                EditorialSectionHeader(title: "Featured Students") {
                    Button { router.openExplore() } label: {
                        Text("See all").font(Theme.Typography.callout.weight(.semibold))
                            .foregroundStyle(Theme.forestGreen)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(directory.students.prefix(4).enumerated()), id: \.element.id) { i, s in
                            NavigationLink { StudentProfileView(student: s) } label: {
                                HomeStudentCard(student: s.card(colorIndex: i), colors: HomeGradients.studentPair(i), style: .featured)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) { BookmarkButton(studentID: s.id).padding(12) }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HairlineDivider()
            Text("Made for curious minds.")
                .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
        }
        .padding(.top, 4)
    }
}

// MARK: - Preview

#Preview {
    HomeView().environmentObject(AppRouter()).environmentObject(SavedStudentsStore()).environmentObject(StudentDirectory())
}
