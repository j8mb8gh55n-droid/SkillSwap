import SwiftUI

struct MessageRequestsView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case received = "Received"
        case sent = "Sent"

        var id: Self { self }
        var state: ChatConversation.State { self == .received ? .pendingIncoming : .pendingOutgoing }
        var rowStatus: String { self == .received ? "Pending introduction" : "Awaiting approval" }
    }

    private struct Page {
        var rows: [ChatConversation] = []
        var offset = 0
        var loaded = false
        var loading = false
        var hasMore = false
        var error: String?
    }

    var previewRequests: [ChatConversation]? = nil
    var previewLoading = false
    @State private var direction = Direction.received
    @State private var pages: [Direction: Page] = [:]
    @State private var selectedConversation: ChatConversation?
    @Environment(\.scenePhase) private var scenePhase
    private let service = MessagingService()
    private let pageSize = 20

    var body: some View {
        VStack(spacing: 0) {
            Picker("Request direction", selection: $direction) {
                ForEach(Direction.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            requestList(direction)
                .id(direction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.warmIvory.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationTitle("Message Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmIvory, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedConversation != nil },
            set: { if !$0 { selectedConversation = nil } }
        )) {
            if let selectedConversation {
                ChatConversationView(conversation: selectedConversation, isPreview: previewRequests != nil)
            }
        }
        .task(id: direction) {
            if scenePhase == .active { await load(direction) }
        }
        .task(id: scenePhase) {
            guard previewRequests == nil, !previewLoading, scenePhase == .active else { return }
            while !Task.isCancelled {
                await load(direction)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onChange(of: selectedConversation?.id) {
            if selectedConversation == nil { Task { await load(direction) } }
        }
    }

    private func requestList(_ option: Direction) -> some View {
        let page = pages[option, default: Page()]
        let rows = previewRequests?.filter { $0.state == option.state } ?? page.rows
        let loaded = previewRequests != nil || page.loaded
        return ScrollView {
            LazyVStack(spacing: 0) {
                if let error = page.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.subheadline)
                        Button("Retry") { Task { await load(option) } }
                            .frame(minHeight: 44)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if !loaded {
                    ProgressView("Loading message requests")
                        .font(.subheadline)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    Text(option == .received ? "No received introductions." : "No sent introductions.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedStone)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(rows) { conversation in
                    Button {
                        selectedConversation = conversation
                    } label: {
                        ChatSummaryRow(conversation: conversation, status: option.rowStatus)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 56)
                }

                if page.hasMore {
                    Button {
                        Task { await load(option, more: true) }
                    } label: {
                        if page.loading { ProgressView().accessibilityLabel("Loading more requests") }
                        else { Text("Load More") }
                    }
                    .frame(minHeight: 44)
                    .disabled(page.loading)
                }
            }
            .padding(.horizontal, 20)
        }
        .refreshable { await load(option) }
    }

    private func load(_ option: Direction, more: Bool = false) async {
        guard previewRequests == nil, !previewLoading else { return }
        var page = pages[option, default: Page()]
        guard !page.loading else { return }
        page.loading = true
        pages[option] = page
        defer {
            page.loading = false
            pages[option] = page
        }
        do {
            let offset = more ? page.offset : 0
            let limit = more ? pageSize : max(pageSize, page.offset)
            let rows = try await service.requests(received: option == .received, offset: offset, limit: limit)
            try Task.checkCancellation()
            let existing = Set(page.rows.map(\.id))
            page.rows = more ? page.rows + rows.filter { !existing.contains($0.id) } : rows
            page.offset = offset + rows.count
            page.hasMore = rows.count == limit
            page.loaded = true
            page.error = nil
        } catch {
            if !MessagingError.cancelled(error) { page.error = MessagingError.text(for: error) }
        }
    }
}
