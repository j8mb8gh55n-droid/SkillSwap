//
//  ExchangeView.swift
//  SkillSwap
//
//  My Exchanges — minimalist, student-centered redesign. Driven by real
//  Supabase data (ExchangeService, read-only) with a clearly-marked demo
//  fallback until the write-flow creates rows. Matches Home/Explore.
//

import SwiftUI

// My Exchanges shows only ongoing work; terminal exchanges live in History.
private enum ExchangeFilter: Equatable { case requests, active }

struct ExchangeView: View {

    @EnvironmentObject private var router: AppRouter

    // MARK: - State
    @StateObject private var profile = ProfileStore()
    @State private var summaries: [ExchangeSummary] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var filter: ExchangeFilter = .active

    private let service = ExchangeService()

    // MARK: - Derived counts (from the actual data source)

    private var requestsCount: Int { summaries.filter { $0.status == .pending }.count }
    private var activeCount: Int { summaries.filter { $0.status == .accepted }.count }

    /// Terminal exchanges shown only in History (completed / cancelled / declined).
    private var historyItems: [ExchangeSummary] {
        summaries.filter { $0.status == .completed || $0.status == .cancelled || $0.status == .declined }
    }

    private var listed: [ExchangeSummary] {
        switch filter {
        case .requests: return summaries.filter { $0.status == .pending }
        case .active:   return summaries.filter { $0.status == .accepted }
        }
    }

    /// Default category: Active if any, else Requests.
    private func defaultFilter() -> ExchangeFilter {
        activeCount > 0 ? .active : (requestsCount > 0 ? .requests : .active)
    }

    private var pendingBinding: Binding<SkillExchange?> {
        Binding(get: { router.pendingExchange }, set: { router.pendingExchange = $0 })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground(tone: .lavender)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if isLoading {
                            loadingRow
                        } else if summaries.isEmpty {
                            firstRunEmptyState
                        } else {
                            segmentedControl
                            swapsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
                .refreshable { await reload() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: pendingBinding) { ex in
                ExchangeDetailsContainer(ex)
            }
        }
        .task { await profile.loadIfNeeded() }
        // Reload on every appear so status changes from the details screen
        // (accept / decline / cancel) are reflected when you return.
        .onAppear { Task { await reload() } }
    }

    /// Loads real exchanges from Supabase. No demo/mock fallback — empty is
    /// shown honestly via the empty state.
    private func reload() async {
        let real = (try? await service.fetchMyExchanges()) ?? []
        summaries = real
        if !didLoad { filter = defaultFilter(); didLoad = true }
        isLoading = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("My Exchanges")
                .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
            Spacer()
            NavigationLink {
                ExchangeHistoryView(summaries: historyItems)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.primaryAction)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exchange History")
        }
        .padding(.top, 4)
    }

    // MARK: - Segmented control (Requests | Active) — full-width iOS style

    @Namespace private var segNamespace

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            segment("Requests", requestsCount, .requests)
            segment("Active", activeCount, .active)
        }
        .padding(4)
        .background(Theme.neutralSurface, in: Capsule())
    }

    private func segment(_ label: String, _ count: Int, _ target: ExchangeFilter) -> some View {
        let active = filter == target
        return Button {
            withAnimation(.snappy(duration: 0.28)) { filter = target }
        } label: {
            Text("\(label) (\(count))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Theme.charcoal : Theme.mutedStone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if active {
                        Capsule().fill(Theme.neutralSelected)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "segment", in: segNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Swaps list

    private var swapsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if listed.isEmpty {
                categoryEmptyState
            } else {
                ForEach(listed) { item in
                    DetailsLink(item) { ExchangeCard(summary: item) }
                }
            }
        }
    }

    @ViewBuilder private var categoryEmptyState: some View {
        switch filter {
        case .requests:
            compactEmpty(title: "No pending requests",
                         message: "New exchange requests will appear here.",
                         showExplore: false)
        case .active:
            compactEmpty(title: "No active swaps yet",
                         message: "Explore skills to start your next exchange.",
                         showExplore: true)
        }
    }

    private func compactEmpty(title: String, message: String, showExplore: Bool) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text(message)
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            if showExplore {
                Button { router.openExplore() } label: {
                    Text("Explore Skills")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Theme.primaryAction).clipShape(Capsule())
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Loading / First-run empty

    private var loadingRow: some View {
        HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }.padding(.vertical, 40)
    }

    private var firstRunEmptyState: some View {
        VStack(spacing: 12) {
            Text("Your first swap starts here.")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.charcoal)
                .multilineTextAlignment(.center)
            Text("Find a student to exchange skills with and your swaps will appear here.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            Button { router.openExplore() } label: {
                Text("Explore Skills")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .softCardShadow()
    }

}

// MARK: - Details link (constructs the SkillExchange the details screen needs)

struct DetailsLink<Label: View>: View {
    @State private var exchange: SkillExchange
    private let label: Label
    init(_ summary: ExchangeSummary, @ViewBuilder label: () -> Label) {
        _exchange = State(initialValue: summary.asExchange)
        self.label = label()
    }
    var body: some View {
        NavigationLink { ExchangeDetailsView(exchange: $exchange) } label: { label }
            .buttonStyle(.plain)
    }
}

/// Wraps a by-value exchange (e.g. deep-linked from Home) so the details
/// screen gets the @Binding it expects.
struct ExchangeDetailsContainer: View {
    @State private var exchange: SkillExchange
    init(_ exchange: SkillExchange) { _exchange = State(initialValue: exchange) }
    var body: some View { ExchangeDetailsView(exchange: $exchange) }
}

// MARK: - Student-centered Exchange Card

struct ExchangeCard: View {
    let summary: ExchangeSummary
    private var url: URL? { summary.otherAvatarURL.flatMap(URL.init(string:)) }
    private var local: String? { summary.otherLocalImage }

    // Friendly status label (derived; no new backend statuses).
    private var statusText: String {
        if summary.status == .accepted && summary.hasConfirmedFutureSession { return "Scheduled" }
        return summary.status.rawValue
    }
    private var statusTint: Color {
        if summary.status == .accepted && summary.hasConfirmedFutureSession { return Theme.powderBlue }
        return summary.status.color
    }

    var body: some View {
        content.padding(16)
            .frame(maxWidth: .infinity)
            .background(
                StudentCardBackground(
                    imageURL: summary.otherAvatarURL,
                    localImageName: local,
                    fallbackColors: summary.bannerColors
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            // Hit-test ONLY the visible rounded card. The background photo uses
            // scaleEffect(1.15), and clipShape clips rendering but NOT hit-testing,
            // so without this the tappable area bled past the card (upward, over the
            // Requests/Active tabs). This confines taps to the card's visible bounds.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                avatar(54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.otherName)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal).lineLimit(1)
                    if let major = summary.otherMajor {
                        Text(major).font(Theme.Typography.meta).foregroundStyle(Theme.charcoal.opacity(0.7)).lineLimit(1)
                    }
                }
                Spacer()
                statusChip
            }

            HStack(alignment: .top, spacing: 14) {
                skillColumn("YOU LEARN", summary.youLearn)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedStone).padding(.top, 14)
                skillColumn("YOU TEACH", summary.youTeach)
            }

            HairlineDivider()

            HStack(spacing: 6) {
                Text(summary.actionLabel)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mutedStone)
            }
        }
    }

    private var statusChip: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.charcoal.opacity(0.75))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(statusTint.opacity(0.5))
            .clipShape(Capsule())
    }

    private func skillColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Theme.charcoal.opacity(0.7))
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.charcoal)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func avatar(_ size: CGFloat) -> some View {
        Group {
            if let local {
                Image(local).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { gradientInitials(size) }
                }
            } else { gradientInitials(size) }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }

    private func gradientInitials(_ size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: summary.bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(summary.otherInitials).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Preview

#Preview {
    ExchangeView().environmentObject(AppRouter())
}
