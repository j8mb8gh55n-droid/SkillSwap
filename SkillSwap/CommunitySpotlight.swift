//
//  CommunitySpotlight.swift
//  SkillSwap
//
//  Phase D3: Community Spotlight — a compact Home section that celebrates real
//  contributors for the current month, plus a dedicated "See all" screen.
//
//  All recognition is VERIFIED server-side by the public.community_spotlight(date)
//  RPC (one featured student per category; counts only; no private exchange
//  rows, participant pairs, messages, or Kudos identities). Nothing here is
//  fabricated — a category with no qualifier simply doesn't appear.
//
//  Reuse: StudentDirectory (already loaded for Home) hydrates winner ids with no
//  extra query in the common case; only ids missing from the directory (e.g. the
//  signed-in user, whom discovery excludes) trigger ONE batched fetch — never
//  N+1. Featured students open the existing StudentProfileView. Styling uses the
//  existing Theme + Monogram, consistent with Featured Students / Hidden Gems.
//

import SwiftUI
import Combine
import Supabase

// MARK: - Category model

enum SpotlightCategory: String, CaseIterable {
    case helpingHand      = "helping_hand"
    case knowledgeSharer  = "knowledge_sharer"
    case communityBuilder = "community_builder"
    case risingStar       = "rising_star"

    var title: String {
        switch self {
        case .helpingHand:      return "Helping Hand"
        case .knowledgeSharer:  return "Knowledge Sharer"
        case .communityBuilder: return "Community Builder"
        case .risingStar:       return "Rising Star"
        }
    }

    var symbol: String {
        switch self {
        case .helpingHand:      return "hand.raised.fill"
        case .knowledgeSharer:  return "lightbulb.fill"
        case .communityBuilder: return "person.2.fill"
        case .risingStar:       return "sparkles"
        }
    }

    /// Pastel accent (kept soft to match the approved system).
    var tint: Color {
        switch self {
        case .helpingHand:      return Theme.brightLavender
        case .knowledgeSharer:  return Theme.mint
        case .communityBuilder: return Theme.blush
        case .risingStar:       return Theme.softPeach
        }
    }

    var order: Int {
        switch self {
        case .helpingHand:      return 0
        case .knowledgeSharer:  return 1
        case .communityBuilder: return 2
        case .risingStar:       return 3
        }
    }

    /// Short, count-based explanation of the achievement (verified number).
    func explanation(count: Int) -> String {
        switch self {
        case .helpingHand:      return "Helped \(count) \(count == 1 ? "peer" : "peers") this month"
        case .knowledgeSharer:  return "Taught \(count) \(count == 1 ? "skill" : "skills") this month"
        case .communityBuilder: return "\(count) \(count == 1 ? "exchange" : "exchanges") completed this month"
        case .risingStar:       return "\(count) \(count == 1 ? "exchange" : "exchanges") as a newcomer"
        }
    }

    /// Eligibility rule (shown on the dedicated screen).
    var rule: String {
        switch self {
        case .helpingHand:      return "Helped at least 2 different students through completed exchanges this month."
        case .knowledgeSharer:  return "Taught at least 2 different skills through completed exchanges this month."
        case .communityBuilder: return "Completed at least 2 skill exchanges this month."
        case .risingStar:       return "Joined within the last 60 days and completed at least one exchange this month."
        }
    }
}

struct SpotlightEntry: Identifiable {
    var id: String { category.rawValue }
    let category: SpotlightCategory
    let count: Int
    let student: DiscoveredStudent
}

// MARK: - Service

struct SpotlightService {

    private let client = SupabaseManager.client

    private struct Response: Decodable {
        let month: String
        let spotlight: [Row]
        struct Row: Decodable { let category: String; let student: String; let count: Int }
    }

    /// Call the verified RPC. `monthStart` nil → current month (SQL default);
    /// otherwise a "yyyy-MM-01" date string for a historical month.
    private func fetchRaw(monthStart: String?) async throws -> Response {
        if let monthStart {
            return try await client
                .rpc("community_spotlight", params: ["target_month": monthStart])
                .execute().value
        } else {
            return try await client
                .rpc("community_spotlight")        // no args → SQL default (current month)
                .execute().value
        }
    }

    /// Resolve winners only through the eligible discovery directory.
    @MainActor
    func fetch(monthStart: String? = nil, directory: StudentDirectory) async throws
        -> (month: String, entries: [SpotlightEntry]) {

        let resp = try await fetchRaw(monthStart: monthStart)
        await directory.refresh()

        let entries = resp.spotlight.compactMap { row -> SpotlightEntry? in
            guard let cat = SpotlightCategory(rawValue: row.category),
                  let student = directory.student(id: row.student) else { return nil }
            return SpotlightEntry(category: cat, count: row.count, student: student)
        }
        .sorted { $0.category.order < $1.category.order }

        return (resp.month, entries)
    }


}

// MARK: - Store (one load, shared by the Home section and the See-all screen)

@MainActor
final class SpotlightStore: ObservableObject {

    enum Phase { case loading, loaded, failed }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var entries: [SpotlightEntry] = []
    @Published private(set) var monthLabel: String = ""

    private let service = SpotlightService()
    private var hasLoaded = false

    func loadIfNeeded(directory: StudentDirectory) async {
        guard !hasLoaded else { return }
        await load(directory: directory)
    }

    func load(directory: StudentDirectory) async {
        phase = .loading
        do {
            let result = try await service.fetch(directory: directory)
            entries = result.entries
            monthLabel = Self.formatMonth(result.month)
            hasLoaded = true
            phase = .loaded
        } catch {
            print("[Spotlight] load failed:", error)
            phase = .failed
        }
    }

    /// "2026-10" → "October 2026" (falls back to the raw value).
    private static func formatMonth(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return ym }
        let names = ["January","February","March","April","May","June",
                     "July","August","September","October","November","December"]
        return "\(names[m - 1]) \(parts[0])"
    }
}

// MARK: - Shared avatar

/// Avatar for a discovered student: remote image if present, else a monogram.
struct SpotlightAvatar: View {
    let student: DiscoveredStudent
    var size: CGFloat = 44
    var body: some View {
        if let url = student.avatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Monogram(initials: student.initials, size: size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(initials: student.initials, size: size)
        }
    }
}

// MARK: - Home section (compact)

struct CommunitySpotlightSection: View {

    @EnvironmentObject private var directory: StudentDirectory
    @StateObject private var store = SpotlightStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(title: "Community Spotlight") {
                NavigationLink { CommunitySpotlightView(store: store) } label: {
                    Text("See all")
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(Theme.forestGreen)
                }
                .buttonStyle(.plain)
            }
            content
        }
        .task { await store.loadIfNeeded(directory: directory) }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }
                .frame(height: 150)

        case .failed:
            infoCard(icon: "exclamationmark.triangle",
                     text: "Couldn't load the spotlight.",
                     action: { Task { await store.load(directory: directory) } })

        case .loaded:
            if store.entries.isEmpty {
                infoCard(icon: "sparkles",
                         text: "No spotlights yet this month — complete exchanges to get featured!")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(store.entries) { entry in
                            NavigationLink { StudentProfileView(student: entry.student) } label: {
                                SpotlightCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2).padding(.bottom, 6)
                }
            }
        }
    }

    private func infoCard(icon: String, text: String, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.mutedStone)
            Text(text).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button("Retry", action: action)
                    .font(Theme.Typography.callout.weight(.semibold)).foregroundStyle(Theme.forestGreen)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Compact spotlight card

struct SpotlightCard: View {
    let entry: SpotlightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryPill
            SpotlightAvatar(student: entry.student, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.student.name)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.charcoal)
                    .lineLimit(1)
                if !entry.student.major.isEmpty {
                    Text(entry.student.major)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.charcoal.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Text(entry.category.explanation(count: entry.count))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 190, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    private var categoryPill: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.category.symbol).font(.system(size: 10, weight: .bold))
            Text(entry.category.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(Theme.charcoal)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(entry.category.tint.opacity(0.55))
        .clipShape(Capsule())
    }
}

// MARK: - Dedicated "See all" screen

struct CommunitySpotlightView: View {

    @ObservedObject var store: SpotlightStore
    @EnvironmentObject private var directory: StudentDirectory
    @Environment(\.dismiss) private var dismiss

    private var entriesByCategory: [SpotlightCategory: SpotlightEntry] {
        Dictionary(uniqueKeysWithValues: store.entries.map { ($0.category, $0) })
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    body(for: store.phase)
                    rulesCard
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadIfNeeded(directory: directory) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { dismiss() } label: {
                BackChevron()
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Community Spotlight").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
            Text(store.monthLabel.isEmpty
                 ? "Celebrating students who make SkillSwap better."
                 : "Celebrating contributors — \(store.monthLabel).")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func body(for phase: SpotlightStore.Phase) -> some View {
        switch phase {
        case .loading:
            HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }.padding(.vertical, 50)

        case .failed:
            stateCard(icon: "exclamationmark.triangle", title: "Couldn't load the spotlight",
                      message: "Please try again.") {
                Button("Retry") { Task { await store.load(directory: directory) } }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(Theme.primaryAction).clipShape(Capsule()).buttonStyle(.plain)
            }

        case .loaded:
            if store.entries.isEmpty {
                stateCard(icon: "sparkles", title: "No spotlights yet this month",
                          message: "Recognition appears as students complete exchanges. Be the first to get featured!") { EmptyView() }
            } else {
                VStack(spacing: 12) {
                    ForEach(SpotlightCategory.allCases.sorted { $0.order < $1.order }, id: \.self) { cat in
                        if let entry = entriesByCategory[cat] { featuredRow(entry) }
                    }
                }
            }
        }
    }

    private func featuredRow(_ entry: SpotlightEntry) -> some View {
        NavigationLink { StudentProfileView(student: entry.student) } label: {
            HStack(spacing: 14) {
                SpotlightAvatar(student: entry.student, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.category.symbol).font(.system(size: 10, weight: .bold))
                        Text(entry.category.title).font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.charcoal)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(entry.category.tint.opacity(0.55)).clipShape(Capsule())

                    Text(entry.student.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
                        .lineLimit(1)
                    Text(entry.category.explanation(count: entry.count))
                        .font(.system(size: 13)).foregroundStyle(Theme.mutedStone).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedStone)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(Theme.primaryAction)
                Text("How recognition works").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            }
            Text("Each month, one student is featured per category based on verified completed exchanges. It's recognition, not a ranking — there are no scores or public leaderboards.")
                .font(.system(size: 13)).foregroundStyle(Theme.mutedStone)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SpotlightCategory.allCases.sorted { $0.order < $1.order }, id: \.self) { cat in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: cat.symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.charcoal)
                        .frame(width: 30, height: 30).background(cat.tint.opacity(0.5)).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.charcoal)
                        Text(cat.rule).font(.system(size: 12)).foregroundStyle(Theme.mutedStone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    private func stateCard<A: View>(icon: String, title: String, message: String, @ViewBuilder action: () -> A) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}
