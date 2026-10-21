//
//  ExchangeHistoryView.swift
//  SkillSwap
//
//  Dedicated destination (NOT a tab) for terminal exchanges — completed,
//  cancelled, and declined. Pushed from the My Exchanges History icon; native
//  back returns without resetting the Requests/Active selection. Reuses the
//  approved ExchangeCard; opens ExchangeDetailsView in a read-only terminal
//  state (details shows no scheduling/accept/cancel actions for terminal rows).
//
//  Data: the same real ExchangeService summaries the Exchange screen loaded,
//  already ordered newest-first (created_at desc). No new table, no mock.
//  LIMITATION: the summary model does not carry a terminal-status timestamp, so
//  cards don't print a completion/cancellation date yet (see report).
//

import SwiftUI

struct ExchangeHistoryView: View {

    let summaries: [ExchangeSummary]

    @Environment(\.dismiss) private var dismiss
    @State private var filter: HistoryFilter = .all

    private enum HistoryFilter: String, CaseIterable {
        case all = "All", completed = "Completed", cancelled = "Cancelled", declined = "Declined"
    }

    private func matches(_ s: ExchangeSummary, _ f: HistoryFilter) -> Bool {
        switch f {
        case .all:       return true
        case .completed: return s.status == .completed
        case .cancelled: return s.status == .cancelled
        case .declined:  return s.status == .declined
        }
    }

    private var listed: [ExchangeSummary] { summaries.filter { matches($0, filter) } }

    var body: some View {
        ZStack {
            AtmosphericBackground(tone: .lavender)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    filterRow
                    if listed.isEmpty {
                        emptyState
                    } else {
                        ForEach(listed) { item in
                            DetailsLink(item) { ExchangeCard(summary: item) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 3) {
                Text("Exchange History")
                    .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
                Text("Your past skill exchanges.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    let selected = filter == f
                    Button {
                        withAnimation(Theme.Motion.standard) { filter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? Theme.charcoal : Theme.mutedStone)
                            .padding(.horizontal, 15).padding(.vertical, 9)
                            .background(selected ? Theme.charcoal.opacity(0.08) : Color.white.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Your story is just getting started.")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
                .multilineTextAlignment(.center)
            Text("Completed and past exchanges will appear here.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}
