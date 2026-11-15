import SwiftUI

struct ChatsView: View {
    enum Inbox {
        case loading
        case loaded([ChatConversation])
        case failed(String)
    }

    var previewInbox: Inbox? = nil
    @State private var inbox: Inbox = .loading
    @State private var refreshError: String?
    @Environment(\.scenePhase) private var scenePhase
    private let service = MessagingService()
    @State private var search = ""
    @State private var showRequests = false
    @State private var deleteSheetHeight: CGFloat = 260
    @State private var deleteTarget: ChatConversation?
    @State private var updatingConversations: Set<UUID> = []
    @State private var inboxRevision = 0
    @State private var preferenceError: String?

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    HStack {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        TextField("Search chats", text: $search)
                            .accessibilityLabel("Search chats")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.vertical, 8)
                .inboxRow(separator: .hidden)

                inboxContent
            }
            .navigationDestination(isPresented: $showRequests) {
                MessageRequestsView(previewRequests: previewConversations)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .alert("Couldn’t update conversation", isPresented: Binding(
                get: { preferenceError != nil },
                set: { if !$0 { preferenceError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(preferenceError ?? "")
            }
            .sheet(item: $deleteTarget) { conversation in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text("Delete conversation?")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("This removes the conversation from your inbox. Your message history is preserved, and a new message can bring it back.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Button(role: .cancel) { deleteTarget = nil } label: {
                                deleteSheetButtonLabel("Cancel")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.surfaceSoft)
                            .foregroundStyle(Theme.ink)
                            Button(role: .destructive) {
                                deleteTarget = nil
                                Task { await updatePreference(for: conversation, delete: true) }
                            } label: {
                                deleteSheetButtonLabel("Delete")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .foregroundStyle(.white)
                            .disabled(updatingConversations.contains(conversation.id) || previewInbox != nil)
                        }
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        deleteSheetHeight = ceil(height)
                    }
                }
                .presentationDetents([.height(deleteSheetHeight)])
                .presentationBackground(Theme.warmIvory)
                .presentationDragIndicator(.visible)
            }
            .refreshable { await reload() }
            .onAppear { Task { await reload() } }
            .task(id: scenePhase) {
                guard previewInbox == nil, scenePhase == .active else { return }
                while !Task.isCancelled {
                    await reload()
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.warmIvory.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .foregroundStyle(Theme.ink)
    }

    private func deleteSheetButtonLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var previewConversations: [ChatConversation]? {
        if case .loaded(let conversations) = previewInbox { return conversations }
        return nil
    }

    private var header: some View {
        let conversations: [ChatConversation] = if case .loaded(let items) = previewInbox ?? inbox {
            items
        } else {
            []
        }
        let incoming = conversations.filter { $0.state == .pendingIncoming }.count

        return HStack(spacing: 12) {
            Text("Chats").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { showRequests = true } label: {
                HStack(spacing: 6) {
                    Text("Requests").font(.subheadline.weight(.semibold))
                    if incoming > 0 {
                        Text(incoming.formatted())
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceSoft, in: Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message Requests")
            .accessibilityValue(incoming > 0 ? "\(incoming) incoming" : "")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var inboxContent: some View {
        if let refreshError {
            VStack(alignment: .leading, spacing: 8) {
                Text(refreshError).font(.footnote).foregroundStyle(.secondary)
                Button("Try Again") { Task { await reload() } }
            }
            .inboxRow(separator: .hidden)
        }
        switch previewInbox ?? inbox {
        case .loading:
            ProgressView("Loading chats")
                .frame(maxWidth: .infinity)
                .padding()
                .inboxRow(separator: .hidden)
        case .failed(let message):
            EmptyStateView(systemImage: "exclamationmark.bubble", title: "Couldn’t load chats",
                           message: message, actionTitle: "Try Again", action: { Task { await reload() } })
                .inboxRow(separator: .hidden)
        case .loaded(let conversations):
            let active = conversations.filter { $0.state != .pendingIncoming && $0.state != .pendingOutgoing }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = active.filter {
                query.isEmpty || $0.participant.name.localizedCaseInsensitiveContains(query)
                    || ($0.latestMessage?.text.localizedCaseInsensitiveContains(query) ?? false)
            }.sorted { $0.latestActivity > $1.latestActivity }

            if visible.isEmpty {
                EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                               title: query.isEmpty ? "No conversations yet" : "No matching conversations",
                               message: query.isEmpty ? "Start a conversation from another student’s profile." : "Try a different name or message.")
                    .inboxRow(separator: .hidden)
            } else {
                Text("Conversations").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    .inboxRow(separator: .hidden)
                ForEach(visible) { conversation in
                    let isUpdating = updatingConversations.contains(conversation.id)
                    NavigationLink {
                        ChatConversationView(conversation: conversation, isPreview: previewInbox != nil)
                    } label: {
                        ChatSummaryRow(conversation: conversation, status: rowStatus(conversation), isUpdating: isUpdating)
                    }
                    .inboxRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if conversation.state == .accepted {
                            Button { deleteTarget = conversation } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            .disabled(isUpdating || previewInbox != nil)
                        }
                        Button { Task { await updatePreference(for: conversation) } } label: {
                            Label(conversation.isMuted ? "Unmute" : "Mute",
                                  systemImage: conversation.isMuted ? "bell" : "bell.slash")
                        }
                        .tint(.gray)
                        .disabled(isUpdating || previewInbox != nil)
                    }
                    .accessibilityActions {
                        if previewInbox == nil && !isUpdating {
                            Button(conversation.isMuted ? "Unmute conversation" : "Mute conversation") {
                                Task { await updatePreference(for: conversation) }
                            }
                            if conversation.state == .accepted {
                                Button("Delete from inbox") { deleteTarget = conversation }
                            }
                        }
                    }
                }
            }
        }
    }
    private func rowStatus(_ conversation: ChatConversation) -> String? {
        switch conversation.state {
        case .declined: return conversation.canReconnect ? "Reconnection available" : "Read-only"
        case .blocked: return "Blocked"
        default: return nil
        }
    }

    private func updatePreference(for conversation: ChatConversation, delete: Bool = false) async {
        guard previewInbox == nil, let id = conversation.serverID,
              case .loaded(let currentRows) = inbox,
              let current = currentRows.first(where: { $0.id == id }),
              !delete || current.state == .accepted,
              updatingConversations.insert(id).inserted else { return }
        let muted = !current.isMuted
        inboxRevision += 1
        defer { updatingConversations.remove(id) }
        do {
            if delete {
                try await service.hide(conversation: id)
            } else {
                try await service.setMuted(muted, in: id)
            }
            if case .loaded(var rows) = inbox, let index = rows.firstIndex(where: { $0.id == id }) {
                if delete {
                    rows.remove(at: index)
                } else {
                    rows[index].isMuted = muted
                }
                inbox = .loaded(rows)
            }
        } catch {
            if !MessagingError.cancelled(error) {
                preferenceError = MessagingError.text(for: error)
            }
        }
    }

    @State private var isRefreshing = false

    private func reload() async {
        guard previewInbox == nil, !isRefreshing, updatingConversations.isEmpty else { return }
        isRefreshing = true
        let revision = inboxRevision
        defer { isRefreshing = false }
        do {
            let conversations = try await service.inbox()
            try Task.checkCancellation()
            guard revision == inboxRevision else { return }
            inbox = .loaded(conversations)
            refreshError = nil
        } catch {
            guard revision == inboxRevision, !MessagingError.cancelled(error) else { return }
            let message = MessagingError.text(for: error)
            if case .loaded = inbox {
                refreshError = message
            } else {
                inbox = .failed(message)
            }
        }
    }
}

private extension View {
    func inboxRow(separator: Visibility = .visible) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(separator)
    }
}

struct ChatSummaryRow: View {
    let conversation: ChatConversation
    var status: String? = nil
    var isUpdating = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ChatAvatar(participant: conversation.participant)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        name
                        Spacer(minLength: 8)
                        timestamp
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        name
                        timestamp
                    }
                }
                if let message = conversation.latestMessage {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let status {
                    Text(status).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if isUpdating {
                ProgressView().accessibilityLabel("Updating conversation")
            } else if conversation.isMuted {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Muted")
            }
            if conversation.unread {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.primaryAction)
                    .accessibilityLabel("\(conversation.unreadCount) unread")
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(conversation.participant.name)
            .font(.headline.weight(conversation.unread ? .bold : .semibold))
    }

    @ViewBuilder private var timestamp: some View {
        if let date = conversation.latestMessage?.sentAt {
            Text(date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ChatAvatar: View {
    let participant: ChatParticipant
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: participant.avatarURL.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                AvatarBadge(initials: participant.initials, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
