//
//  StudentStatsView.swift
//  SkillSwap
//
//  Phase D2: Verified Statistics & Achievements.
//
//  Every number here is VERIFIED server-side — exchange stats come from the
//  public.student_stats(student) RPC and the kudos total from kudos_count(),
//  both SECURITY DEFINER aggregates that return counts only. Nothing on this
//  screen is fabricated client-side; achievements are derived purely from those
//  verified counts. Reusable content blocks (grid + achievements) so both
//  My Profile and another student's profile can present the same honest data.
//

import SwiftUI

// MARK: - Achievement model

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String        // what unlocks it (always shown, locked or not)
    let symbol: String
    let tint: Color
    let unlocked: Bool
}

enum Achievements {

    /// Derive the six approved badges from verified counts only. Order is the
    /// approved spec order and stable so the strip doesn't reshuffle. `kudosTotal`
    /// is accepted for parity with the stats screen but no current badge keys off
    /// the raw total — SkillSwap Star uses DISTINCT givers (kudosDistinctGivers).
    static func all(stats: StudentStats, kudosTotal: Int = 0) -> [Achievement] {
        [
            Achievement(
                id: "first_swap", title: "First Swap",
                detail: "Complete 1 exchange",
                symbol: "sparkles", tint: Theme.brightLavender,
                unlocked: stats.completedSwaps >= 1),
            Achievement(
                id: "helping_hand", title: "Helping Hand",
                detail: "Help 3 students",
                symbol: "person.2.fill", tint: Theme.powderBlue,
                unlocked: stats.studentsHelped >= 3),
            Achievement(
                id: "knowledge_sharer", title: "Knowledge Sharer",
                detail: "Teach 3 skills",
                symbol: "lightbulb.fill", tint: Theme.mint,
                unlocked: stats.skillsShared >= 3),
            Achievement(
                id: "community_builder", title: "Community Builder",
                detail: "Complete 5 exchanges",
                symbol: "arrow.triangle.2.circlepath", tint: Theme.powderBlue,
                unlocked: stats.completedSwaps >= 5),
            Achievement(
                id: "skillswap_star", title: "SkillSwap Star",
                detail: "Kudos from 5 students",
                symbol: "star.fill", tint: Color(hex: 0xFCE3A2),
                unlocked: stats.kudosDistinctGivers >= 5),
            Achievement(
                id: "skill_explorer", title: "Skill Explorer",
                detail: "Learn 3 skills",
                symbol: "book.closed.fill", tint: Theme.brightLavender,
                unlocked: stats.skillsExplored >= 3),
        ]
    }

    static func unlockedCount(stats: StudentStats) -> Int {
        all(stats: stats).filter(\.unlocked).count
    }
}

// MARK: - Verified stats grid (reusable content block)

/// A 2×2 grid of the four approved verified statistics. Skills Explored and
/// distinct Kudos givers are still computed (for achievements) but are NOT shown
/// as main stats. Kudos Received here is the total from kudos_count().
struct VerifiedStatsGrid: View {

    let stats: StudentStats
    let kudosReceived: Int

    private var tiles: [(value: Int, label: String, symbol: String, color: Color)] {
        [
            (stats.completedSwaps, "Completed Swaps", "checkmark.seal.fill", Theme.brightLavender.opacity(0.55)),
            (stats.skillsShared, "Skills Shared", "lightbulb.fill", Theme.mint.opacity(0.6)),
            (stats.studentsHelped, "Students Helped", "person.2.fill", Theme.powderBlue.opacity(0.6)),
            (kudosReceived, "Kudos Received", "heart.fill", Color(hex: 0xF6C9D4).opacity(0.7)),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(tiles, id: \.label) { t in
                StatTile(value: "\(t.value)", label: t.label, systemImage: t.symbol, color: t.color)
            }
        }
    }
}

// MARK: - Achievements strip (reusable content block)

struct AchievementsStrip: View {

    let achievements: [Achievement]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(achievements) { badge(for: $0) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func badge(for a: Achievement) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(a.unlocked ? a.tint : Theme.hairline)
                    .frame(width: 52, height: 52)
                Image(systemName: a.unlocked ? a.symbol : "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(a.unlocked ? Theme.charcoal : Theme.charcoal.opacity(0.6))
            }
            Text(a.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(a.unlocked ? Theme.charcoal : Theme.charcoal.opacity(0.78))
                .lineLimit(1)
            Text(a.detail)
                .font(.system(size: 10))
                .foregroundStyle(a.unlocked ? Theme.mutedStone : Theme.charcoal.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 104)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).stroke(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.title), \(a.unlocked ? "unlocked" : "locked"). \(a.detail)")
    }
}

// MARK: - Preview

#Preview {
    let stats = StudentStats(
        completedSwaps: 6, skillsShared: 3, studentsHelped: 4,
        skillsExplored: 2, kudosDistinctGivers: 5)
    return ScrollView {
        VStack(spacing: 20) {
            VerifiedStatsGrid(stats: stats, kudosReceived: 11)
            AchievementsStrip(achievements: Achievements.all(stats: stats))
        }
        .padding()
    }
    .background(Theme.warmIvory)
}
