//
//  NotificationsView.swift
//  SkillSwap
//
//  Minimal, native in-app notification list for exchange/session events.
//  Reads real notifications via NotificationService (recipient-scoped). No
//  mock data: until phase3_notifications.sql is applied the list is simply
//  empty. Tapping an item marks it read and takes the user to the Exchanges
//  tab (deep-link to the specific exchange is pending the exchange write-flow).
//

import SwiftUI

struct NotificationsView: View {

    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var items: [AppNotification] = []
    @State private var isLoading = true
    @State private var loadError = false

    private let service = NotificationService()

    var body: some View {
        ZStack {
            AtmosphericBackground(tone: .lavender)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isLoading {
                        ProgressView().tint(Theme.primaryAction)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if loadError {
                        errorState
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button { open(item) } label: { row(item) }
                                    .buttonStyle(.plain)
                                if item.id != items.last?.id { HairlineDivider() }
                            }
                        }
                        .background(Theme.surface.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = false
        do {
            items = try await service.fetch()
        } catch {
            print("[Notifications] load failed:", error)
            loadError = true
        }
        isLoading = false
    }

    private var hasUnread: Bool { items.contains { !$0.isRead } }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.charcoal)
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Back")
                Spacer()
                if hasUnread {
                    Button("Mark all read") {
                        Task { try? await service.markAllRead(); await load() }
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                }
            }
            Text("Notifications")
                .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    // MARK: - Row

    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
                Text(item.detail)
                    .font(.system(size: 13)).foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = item.createdAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11)).foregroundStyle(Theme.mutedStone.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
            if !item.isRead {
                Circle().fill(Theme.primaryAction).frame(width: 8, height: 8).padding(.top, 5)
            }
        }
        .padding(14)
        .background(item.isRead ? Color.clear : Theme.brightLavender.opacity(0.14))
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
            .font(.system(size: 16)).foregroundStyle(Theme.primaryAction)
            .frame(width: size, height: size)
            .background(Theme.brightLavender.opacity(0.35)).clipShape(Circle())
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26)).foregroundStyle(Theme.primaryAction)
            Text("You're all caught up")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text("Updates about your exchange requests and sessions will appear here.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
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
                    .background(Theme.primaryAction).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Open

    private func open(_ item: AppNotification) {
        Task { try? await service.markRead(item.id) }
        // Deep-link to the specific exchange needs a fetch-by-id (pending the
        // exchange write-flow); for now route to the Exchanges tab.
        dismiss()
        router.tab = .exchanges
    }
}
