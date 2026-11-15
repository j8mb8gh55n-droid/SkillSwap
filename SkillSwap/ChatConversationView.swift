import SwiftUI

struct ChatConversationView: View {
    enum SendState {
        case unavailable, ready, sending, failed
    }

    @State private var conversation: ChatConversation
    private let isPreview: Bool
    private let sendState: SendState
    private let service = MessagingService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var loaded = false
    @State private var refreshing = false
    @State private var sending = false
    @State private var draftingReconnection = false
    @State private var responding = false
    @State private var blocking = false
    @State private var ownsBlock: Bool?
    @State private var confirmUnblock = false
    @State private var confirmBlock = false
    @State private var showExchange = false
    @State private var showStudentProfile = false
    @State private var showReport = false
    @State private var unavailableFeature: String?
    @State private var safetyError: String?
    @State private var confirmDecline = false
    @State private var responseError: String?
    @State private var hasOlderMessages = false
    @State private var markedThrough: Int64?
    @State private var refreshError: String?
    @State private var sendError: String?
    @State private var acknowledgedMessage: Int64?
    @State private var openingIntroduction = false
    @State private var scrollToLatest = false

    init(conversation: ChatConversation, isPreview: Bool = false,
         sendState: SendState = .unavailable, initialDraft: String = "", previewOwnsBlock: Bool? = nil) {
        _conversation = State(initialValue: conversation)
        _draft = State(initialValue: initialDraft)
        _ownsBlock = State(initialValue: isPreview ? previewOwnsBlock : nil)
        self.isPreview = isPreview
        self.sendState = sendState
    }
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @Environment(\.chatDraftStore) private var draftStore

    private var draftKey: UUID { conversation.participant.id }
    private let messageLimit = 2000

    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { updateDraft($0) })
    }

    private func updateDraft(_ text: String) {
        draft = text
        if !isPreview { draftStore?.save(text, for: draftKey) }
    }
    @ScaledMetric(relativeTo: .body) private var nameSize = 17

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if let exchangeContext = conversation.exchangeContext {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Related exchange", systemImage: "arrow.left.arrow.right")
                                .font(.subheadline.weight(.semibold))
                            Text(exchangeContext).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let refreshError {
                        Text(refreshError).font(.footnote).foregroundStyle(.secondary)
                        Button("Refresh Conversation") { Task { await refresh() } }
                    } else if !loaded && !isPreview {
                        ProgressView("Loading conversation")
                    }
                    if hasOlderMessages {
                        Button("Load Older Messages") { Task { await loadOlder() } }
                            .disabled(refreshing || sending)
                    }

                    if (loaded || isPreview) && conversation.state == .introduction {
                        introduction
                    }

                    ForEach(conversation.messages.sorted { $0.id < $1.id }) { message in
                        messageBubble(message)
                    }
                    Color.clear.frame(height: 0).id("latest-message")
                }
                .padding(20)
            }
            .onChange(of: scrollToLatest) {
                proxy.scrollTo("latest-message", anchor: .bottom)
            }
        }
        .onAppear {
            if !isPreview, let draftStore { draft = draftStore.text(for: draftKey) }
        }
        .alert("Decline introduction?", isPresented: $confirmDecline) {
            Button("Cancel", role: .cancel) {}
            Button("Decline", role: .destructive) { Task { await respond(accept: false) } }
        } message: {
            Text(conversation.reconnectionMessage == nil ? ChatConversation.declineExplanation : "Declining closes this reconnection request permanently.")
        }
        .alert("Block student?", isPresented: $confirmBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) { Task { await updateBlock(block: true) } }
        } message: {
            Text("Blocking stops both of you from sending messages in this conversation.")
        }
        .alert("Unblock student?", isPresented: $confirmUnblock) {
            Button("Cancel", role: .cancel) {}
            Button("Unblock") { Task { await updateBlock(block: false) } }
        } message: {
            Text(BlockedStudentsView.unblockExplanation)
        }
        .onReceive(NotificationCenter.default.publisher(for: BlockedStudentsView.blocksChanged)) { _ in
            Task { await refresh() }
        }
        .alert("Unavailable", isPresented: Binding(
            get: { unavailableFeature != nil },
            set: { if !$0 { unavailableFeature = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unavailableFeature ?? "")
        }
        .sheet(isPresented: $showReport) {
            if let id = conversation.serverID {
                ChatReportSheet(conversationID: id, evidence: conversation.messages.filter { !$0.sentByMe })
            }
        }
        .navigationDestination(isPresented: $showExchange) {
            ChatExchangeView(participant: conversation.participant)
        }
        .navigationDestination(isPresented: $showStudentProfile) {
            ChatParticipantProfileView(studentID: conversation.participant.id)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard !isPreview, scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .foregroundStyle(Theme.ink)
        .background(Theme.warmIvory.ignoresSafeArea())
    }

    private var introduction: some View {
        VStack(spacing: 8) {
            Image(systemName: "message")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Send an introduction")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Introduce yourself or mention a skill you’d like to exchange.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                BackChevron()
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Button {
                showStudentProfile = true
            } label: {
                HStack(spacing: 12) {
                    ChatAvatar(participant: conversation.participant, size: 44)
                    Text(conversation.participant.name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPreview)
            .accessibilityLabel("View profile for \(conversation.participant.name)")
            Spacer(minLength: 0)
            if loaded || isPreview {
                Menu {
                    if ownsBlock == true {
                        Button("Unblock Student") { confirmUnblock = true }
                    } else if conversation.state != .blocked || ownsBlock == false {
                        Button("Block Student", role: .destructive) { confirmBlock = true }
                    }
                    #if CHAT_REPORTING_ENABLED
                    if conversation.serverID != nil && !isPreview {
                        Button("Report Student") { showReport = true }
                    }
                    #endif
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuOrder(.fixed)
                .accessibilityLabel("Conversation actions")
                .disabled(blocking || refreshing || sending || responding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if blocking { ProgressView("Updating block") }
            if let safetyError {
                Text(safetyError).font(.footnote).foregroundStyle(.secondary)
            }
            if let status = sendError ?? ((loaded || isPreview) ? statusMessage : nil) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if (loaded || isPreview) && conversation.state == .pendingIncoming {
                if let responseError {
                    Text(responseError).font(.footnote).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { approvalActions }
                    VStack(alignment: .leading, spacing: 8) { approvalActions }
                }
                .disabled(responding || refreshing || isPreview)
            }

            if loaded && conversation.canReconnect && !draftingReconnection && refreshError == nil {
                Button("Request to reconnect") { draftingReconnection = true }
                    .frame(minHeight: 44)
            }

            if (loaded || isPreview) && showsComposer {
                if messageLength >= messageLimit - 100 {
                    Text("\(messageLength.formatted()) / \(messageLimit.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(messageLength > messageLimit ? Color.red : Color.secondary)
                        .accessibilityLabel("\(messageLength) of \(messageLimit) characters")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack(alignment: .center, spacing: 8) {
                    if conversation.state == .accepted {
                        Menu {
                            Button { showExchange = true } label: {
                                Label("Exchange", systemImage: "arrow.left.arrow.right")
                            }
                            Button {
                                unavailableFeature = "Camera attachments require private messaging storage."
                            } label: {
                                Label("Camera · Unavailable", systemImage: "camera")
                            }
                            Button {
                                unavailableFeature = "Photo attachments require private messaging storage."
                            } label: {
                                Label("Photos · Unavailable", systemImage: "photo")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Add to conversation")
                        .disabled(blocking || sending)
                    }
                    HStack(alignment: .center, spacing: 4) {
                        TextField(draftingReconnection ? "Write a reconnection request" : conversation.state == .introduction ? "Write an introduction" : "Write a message",
                                  text: draftBinding, axis: .vertical)
                            .lineLimit(1...4)
                            .disabled(sending)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                            .padding(.vertical, 8)
                        sendButton
                            .padding(.trailing, 2)
                    }
                    .frame(minHeight: 44)
                    .background(Theme.surfaceSoft, in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private var approvalActions: some View {
        Group {
            Button { Task { await respond(accept: true) } } label: {
                Text("Accept")
                    .padding(.horizontal, 16)
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(.white)
                    .background(Theme.primaryAction, in: Capsule())
            }
            Button { confirmDecline = true } label: {
                Text("Decline")
                    .padding(.horizontal, 16)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.surfaceSoft, in: Capsule())
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
        .opacity(responding ? 0.55 : 1)
    }

    private func respond(accept: Bool) async {
        guard !isPreview, !responding, !blocking, !refreshing, conversation.state == .pendingIncoming,
              let id = conversation.serverID else { return }
        responding = true
        responseError = nil
        do {
            if let message = conversation.reconnectionMessage {
                try await service.respondToReconnection(in: id, message: message, accept: accept)
            } else {
                try await service.respond(to: id, accept: accept)
            }
        } catch {
            if !MessagingError.cancelled(error) { responseError = MessagingError.text(for: error) }
        }
        responding = false
        await refresh()
    }

    private var showsComposer: Bool {
        conversation.state == .accepted || conversation.state == .introduction ||
            (conversation.canReconnect && draftingReconnection)
    }

    private var messageBody: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasDraft: Bool { !messageBody.isEmpty }
    private var messageLength: Int { messageBody.unicodeScalars.count }

    private var canSend: Bool {
        let valid = showsComposer && hasDraft && messageLength <= messageLimit
        if isPreview { return valid && (sendState == .ready || sendState == .failed) }
        return valid && loaded && !sending && !responding && !blocking && !refreshing && acknowledgedMessage == nil && refreshError == nil
    }

    private var sendButton: some View {
        let inProgress = sending || (isPreview && sendState == .sending)
        let highlighted = hasDraft || inProgress
        return Button {
            Task { await send() }
        } label: {
            Group {
                if inProgress {
                    ProgressView().tint(Theme.ink)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(highlighted ? Theme.ink : Color.secondary)
            .glassEffect(
                highlighted ? .regular.tint(Theme.softMint.opacity(0.65)).interactive() : .regular,
                in: .circle
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(inProgress ? "Sending" : "Send")
    }

    private var statusMessage: String? {
        if sending || (isPreview && sendState == .sending) { return "Sending…" }
        if messageLength > messageLimit { return "Use 2,000 characters or fewer." }
        if isPreview && sendState == .failed { return "Message couldn’t be sent. Try again." }

        switch conversation.state {
        case .introduction, .accepted: return isPreview ? "Preview only" : nil
        case .pendingIncoming: return responding ? "Updating request…" : "Accept this introduction to reply and continue the conversation."
        case .pendingOutgoing: return "Awaiting approval. You can send more messages after your introduction is accepted."
        case .declined: return conversation.canReconnect ? "You can send one reconnection request. Messaging resumes if the other student accepts." : "This conversation is read-only."
        case .blocked: return "Messaging is unavailable for this conversation."
        }
    }

    private func refresh() async {
        guard !isPreview, !refreshing, !sending, !responding, !blocking, !confirmBlock, !confirmUnblock, !showExchange, !showStudentProfile, !confirmDecline else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            var updated = try await service.conversation(for: conversation.participant, id: conversation.serverID)
            if let id = updated.serverID {
                let previous = loaded ? conversation.messages : []
                var newest = previous.map(\.id).max()
                var messages = previous
                if newest == nil {
                    let page = try await service.messages(in: id)
                    messages = page
                    hasOlderMessages = page.count == MessagingService.pageSize
                } else {
                    while let cursor = newest {
                        let page = try await service.messages(in: id, after: cursor)
                        messages += page
                        if page.count < MessagingService.pageSize { break }
                        newest = page.last?.id
                    }
                }
                updated.messages = messages
            }
            try Task.checkCancellation()
            guard !sending, !blocking else { return }
            let shouldScroll = !loaded || conversation.messages.map(\.id).max() != updated.messages.map(\.id).max()
            updated.exchangeContext = conversation.exchangeContext
            conversation = updated
            if !updated.canReconnect { draftingReconnection = false }
            loaded = true
            refreshError = nil
            if updated.state == .blocked {
                do {
                    ownsBlock = try await service.ownsBlock(on: updated.participant.id)
                } catch {
                    ownsBlock = nil
                    throw error
                }
            } else {
                ownsBlock = false
            }
            if let acknowledgedMessage, updated.messages.contains(where: { $0.id == acknowledgedMessage }) {
                self.acknowledgedMessage = nil
            }
            if openingIntroduction {
                openingIntroduction = false
                if updated.state == .accepted {
                    sendError = "This conversation is already open. Tap Send to send your draft."
                }
            }
            if updated.state == .pendingOutgoing,
               updated.messages.contains(where: { $0.sentByMe && $0.text == draft.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                updateDraft("")
                sendError = nil
            }
            if shouldScroll { scrollToLatest.toggle() }
            if let id = updated.serverID, let latest = updated.messages.max(by: { $0.id < $1.id }),
               markedThrough != latest.id {
                try await service.markRead(in: id, through: latest.id)
                markedThrough = latest.id
            }
        } catch {
            if !MessagingError.cancelled(error) { refreshError = MessagingError.text(for: error) }
        }
    }

    private func updateBlock(block: Bool) async {
        guard !isPreview, !blocking, !refreshing, !sending, !responding,
              block ? (conversation.state != .blocked || ownsBlock == false) : ownsBlock == true else { return }
        blocking = true
        safetyError = nil
        do {
            if block {
                try await service.block(student: conversation.participant.id)
                conversation.state = .blocked
            } else {
                try await service.unblock(student: conversation.participant.id)
            }
            ownsBlock = nil
            sendError = nil
            NotificationCenter.default.post(name: BlockedStudentsView.blocksChanged, object: nil)
        } catch {
            if !MessagingError.cancelled(error) { safetyError = MessagingError.text(for: error) }
        }
        blocking = false
        await refresh()
    }

    private func loadOlder() async {
        guard !refreshing, !sending, !responding, !blocking, let id = conversation.serverID,
              let oldest = conversation.messages.map(\.id).min() else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let page = try await service.messages(in: id, before: oldest)
            try Task.checkCancellation()
            conversation.messages += page
            hasOlderMessages = page.count == MessagingService.pageSize
        } catch {
            if !MessagingError.cancelled(error) { refreshError = MessagingError.text(for: error) }
        }
    }

    private func send() async {
        guard !isPreview, canSend, !refreshing, acknowledgedMessage == nil else { return }
        let body = messageBody
        sending = true
        sendError = nil
        do {
            if let id = conversation.serverID {
                if conversation.canReconnect && draftingReconnection {
                    acknowledgedMessage = try await service.reconnect(to: id, body: body)
                    conversation.canReconnect = false
                    draftingReconnection = false
                } else {
                    acknowledgedMessage = try await service.send(to: id, body: body)
                }
                updateDraft("")
            } else {
                let id = try await service.introduce(to: conversation.participant.id, body: body)
                conversation.serverID = id
                loaded = false
                // An accepted pair can be returned without inserting the introduction.
                openingIntroduction = true
            }
        } catch {
            if !MessagingError.cancelled(error) {
                sendError = error is URLError
                    ? "Delivery couldn’t be confirmed. Refresh and check the history before trying again."
                    : MessagingError.text(for: error)
            }
        }
        sending = false
        await refresh()
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.sentByMe ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .padding(12)
                .foregroundStyle(message.sentByMe ? Color.black.opacity(0.84) : Theme.ink)
                .background(message.sentByMe ? Theme.softMint : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 16))
            Text(message.sentAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: message.sentByMe ? .trailing : .leading)
        .padding(message.sentByMe ? .leading : .trailing, 32)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("\(message.sentByMe ? "You" : conversation.participant.name), \(message.text), \(message.sentAt.formatted(.dateTime.hour().minute()))")
    }
}


private struct ChatParticipantProfileView: View {
    let studentID: UUID
    @State private var student: DiscoveredStudent?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        if let student {
            StudentProfileView(student: student, returnsToConversation: true)
        } else {
            Group {
                if loading {
                    ProgressView("Loading student profile")
                } else {
                    ContentUnavailableView {
                        Label("Profile unavailable", systemImage: "person.crop.circle")
                    } description: {
                        Text(failed ? "Check your connection and try again." : "This student’s public profile is unavailable.")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.warmIvory.ignoresSafeArea())
            .navigationTitle("Student Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        failed = false
        defer { loading = false }
        do {
            student = try await StudentDiscoveryService().fetchProfile(id: studentID)
        } catch {
            if !MessagingError.cancelled(error) { failed = true }
        }
    }
}


@MainActor
final class ChatDraftStore {
    private var drafts: [UUID: String] = [:]

    func text(for participant: UUID) -> String { drafts[participant] ?? "" }

    func save(_ text: String, for participant: UUID) {
        drafts[participant] = text.isEmpty ? nil : text
    }
}

private struct ChatDraftStoreKey: EnvironmentKey {
    static let defaultValue: ChatDraftStore? = nil
}

extension EnvironmentValues {
    var chatDraftStore: ChatDraftStore? {
        get { self[ChatDraftStoreKey.self] }
        set { self[ChatDraftStoreKey.self] = newValue }
    }
}
