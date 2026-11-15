//
//  NotificationsView.swift
//  SkillSwap
//
import SwiftUI

struct NotificationsView: View {
    private enum ReadOperation: Equatable {
        case all
        case open(String)
    }

    let onReadChange: () -> Void

    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var appearance

    @State private var items: [AppNotification] = []
    @State private var isLoading = true
    @State private var loadError = false
    @State private var operation: ReadOperation?
    @State private var failedOperation: ReadOperation?
    @State private var operationError = ""
    @State private var selectedExchange: SkillExchange?

    private let service = NotificationService()
    private let headerSideWidth: CGFloat = 84

    private var accent: Color {
        appearance == .dark ? Theme.powderBlue : Color(hex: 0x4A577D)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(tone: .lavender)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let failedOperation {
                        readError(for: failedOperation)
                    }
                    if isLoading && items.isEmpty {
                        ProgressView().tint(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        if loadError { errorState }
                        if items.isEmpty && !loadError { emptyState }
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                Button { start(.open(item.id)) } label: { row(item) }
                                    .buttonStyle(.plain)
                                    .disabled(operation != nil || isLoading)
                                    .accessibilityValue(item.isRead ? "Read" : "Unread")
                                if item.id != items.last?.id { HairlineDivider() }
                            }
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
        .navigationDestination(item: $selectedExchange) { exchange in
            ExchangeDetailsContainer(exchange)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
        .task { await load() }
        .task(id: operation) {
            if let operation { await perform(operation) }
        }
    }

    private func load() async {
        isLoading = true
        loadError = false
        defer { isLoading = false }
        do {
            let updated = try await service.fetch()
            try Task.checkCancellation()
            items = updated
        } catch {
            if !Task.isCancelled { loadError = true }
        }
    }

    private var hasUnread: Bool { items.contains { !$0.isRead } }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                BackChevron().foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            .frame(width: headerSideWidth, alignment: .leading)

            Text("Notifications")
                .font(.headline).foregroundStyle(Theme.charcoal)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityAddTraits(.isHeader)

            Button { start(.all) } label: {
                Group {
                    if operation == .all {
                        ProgressView().tint(accent)
                    } else {
                        Text("Mark all read")
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(hasUnread ? accent : Theme.mutedStone)
                .frame(width: headerSideWidth, alignment: .trailing)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(operation == .all ? "Marking all notifications read" : "Mark all read")
            .disabled(!hasUnread || operation != nil || isLoading)
        }
        .padding(.top, 4)
    }

    // MARK: - Row

    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(item)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = item.createdAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                }
            }
            Spacer(minLength: 0)
            if operation == .open(item.id) {
                ProgressView().accessibilityLabel("Opening notification")
            } else if !item.isRead {
                Circle().fill(accent).frame(width: 8, height: 8).padding(.top, 5)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            Theme.surface
            if !item.isRead { Theme.periwinkle.opacity(appearance == .dark ? 0.12 : 0.24) }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func avatar(_ item: AppNotification) -> some View {
        let size: CGFloat = 40
        if let url = item.actorAvatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { symbolAvatar(item, size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            symbolAvatar(item, size)
        }
    }

    private func symbolAvatar(_ item: AppNotification, _ size: CGFloat) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: 16)).foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.brightLavender.opacity(0.35)).clipShape(Circle())
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26)).foregroundStyle(Theme.ink)
            Text("You're all caught up")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text("Updates about your exchange requests and sessions will appear here.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 20)
    }

    // MARK: - Error

    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text("Couldn't load notifications")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text("Please check your connection and try again.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Text("Retry").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .disabled(isLoading || operation != nil)
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    private func readError(for operation: ReadOperation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(operationError).foregroundStyle(Theme.validationText)
            Button("Retry") { start(operation) }
                .font(Theme.Typography.callout.weight(.semibold))
                .foregroundStyle(accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .disabled(self.operation != nil || isLoading)
        }
        .font(Theme.Typography.callout)
    }

    private func start(_ request: ReadOperation) {
        guard operation == nil, selectedExchange == nil, !isLoading else { return }
        failedOperation = nil
        operation = request
    }

    private func perform(_ request: ReadOperation) async {
        defer { operation = nil }
        var errorMessage = "Couldn’t update read status."
        do {
            switch request {
            case .all:
                let updatedIDs = try await service.markAllRead()
                updateReadStates(ids: updatedIDs)
                await load()
            case .open(let id):
                guard let item = items.first(where: { $0.id == id }) else { return }
                if !item.isRead {
                    try await service.markRead(id)
                    updateReadStates(ids: [id])
                }
                errorMessage = "Couldn’t open the exchange."
                if let exchangeID = item.exchangeID.flatMap(UUID.init(uuidString:)),
                   let exchange = try await ExchangeService().fetchExchange(id: exchangeID) {
                    try Task.checkCancellation()
                    selectedExchange = exchange
                    return
                }
                try Task.checkCancellation()
                dismiss()
                router.tab = .exchanges
            }
        } catch {
            if !Task.isCancelled {
                operationError = errorMessage
                failedOperation = request
            }
        }
    }

    private func updateReadStates(ids: Set<String>) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].isRead = true
        }
        onReadChange()
    }
}
