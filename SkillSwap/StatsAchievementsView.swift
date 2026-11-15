//
//  StatsAchievementsView.swift
//  SkillSwap
//
//  Phase D2: the dedicated "Your Impact" screen for the signed-in student —
//  pushed from the small nav card on ProfileView (keeps the Profile page
//  uncluttered). Shows the four verified statistics (student_stats + kudos_count
//  RPCs) and the six achievement badges derived from those verified counts.
//
//  Loads fresh every time it's pushed (so it reflects newly completed exchanges
//  or Kudos), resolves the CURRENT session user inside the service on each load
//  (never a cached id → no stale data across account switches), and handles
//  loading / empty / success / error explicitly — Supabase errors are surfaced,
//  never swallowed.
//

import SwiftUI

struct StatsAchievementsView: View {

    @Environment(\.dismiss) private var dismiss
    private let service = ExchangeService()

    private enum LoadState {
        case loading
        case loaded(StudentStats, kudos: Int)
        case failed
    }

    @State private var state: LoadState = .loading

    var body: some View {
        ZStack {
            Theme.warmIvory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }          // runs on each push → always fresh
    }

    // MARK: - Load

    private func load() async {
        state = .loading
        do {
            // One round-trip each, in parallel — no N+1, no duplicate fetching.
            async let statsCall = service.myStats()
            async let kudosCall = service.myKudosCount()
            let (stats, kudos) = try await (statsCall, kudosCall)
            state = .loaded(stats, kudos: kudos)
        } catch {
            print("[Stats] load failed:", error)
            state = .failed
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                BackChevron()
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Your Impact").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    // MARK: - Content (state machine)

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            HStack { Spacer(); ProgressView().tint(Theme.ink); Spacer() }
                .padding(.vertical, 60)

        case .failed:
            errorState

        case let .loaded(stats, kudos):
            statsSection(stats, kudos: kudos)
            achievementsSection(stats, kudos: kudos)
            if stats.isEmpty && kudos == 0 { emptyNote }
        }
    }

    private func statsSection(_ stats: StudentStats, kudos: Int) -> some View {
        card(title: "Statistics", symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 10) {
                VerifiedStatsGrid(stats: stats, kudosReceived: kudos)
                Text("Verified from your completed exchanges.")
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedStone)
            }
        }
    }

    private func achievementsSection(_ stats: StudentStats, kudos: Int) -> some View {
        let badges = Achievements.all(stats: stats, kudosTotal: kudos)
        return card(title: "Achievements", symbol: "rosette") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(badges.filter(\.unlocked).count) of \(badges.count) unlocked")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mutedStone)
                AchievementsStrip(achievements: badges)
            }
        }
    }

    private var emptyNote: some View {
        Text("Complete your first exchange to start earning stats and badges.")
            .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text("Couldn't load your impact").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text("Please check your connection and try again.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone).multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Text("Retry").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Card wrapper (matches ProfileView's section styling)

    private func card<Content: View>(title: String, symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.ink)
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
}

#Preview {
    NavigationStack { StatsAchievementsView() }
}
