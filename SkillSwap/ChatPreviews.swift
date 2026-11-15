#if DEBUG
import SwiftUI

private let maya = ChatParticipant(id: UUID(), name: "Maya Chen", initials: "MC", avatarURL: nil)
private let omar = ChatParticipant(id: UUID(), name: "Omar Ali", initials: "OA", avatarURL: nil)
private let lina = ChatParticipant(id: UUID(), name: "Lina Patel", initials: "LP", avatarURL: nil)

private let incoming = ChatConversation(
    participant: omar, state: .pendingIncoming,
    messages: [ChatMessage(id: 1, text: "Hi! Would you like to trade drawing tips for a Swift lesson?", sentByMe: false, sentAt: .now)]
)
private let outgoing = ChatConversation(
    participant: lina, state: .pendingOutgoing,
    messages: [ChatMessage(id: 2, text: "Hi! I saw you’re learning photography. I’d love to help.", sentByMe: true, sentAt: .now)]
)
private let accepted = ChatConversation(
    participant: maya, state: .accepted,
    messages: [
        ChatMessage(id: 3, text: "Would the library work for our sketching session?", sentByMe: true, sentAt: .now.addingTimeInterval(-120)),
        ChatMessage(id: 4, text: "Yes, the library sounds good!", sentByMe: false, sentAt: .now)
    ],
    unreadCount: 1, latestActivity: .now,
    exchangeContext: "Sketching and Swift"
)

private func sampleThreads(_ count: Int, state: ChatConversation.State) -> [ChatConversation] {
    (1...count).map { index in
        ChatConversation(
            participant: ChatParticipant(id: UUID(), name: "Alexandra Fernández de la Cruz \(index)",
                                         initials: "AF", avatarURL: nil),
            state: state,
            messages: [ChatMessage(id: Int64(index), text: "Would you like to talk about the next design workshop?",
                                   sentByMe: state == .pendingOutgoing, sentAt: .now.addingTimeInterval(-Double(index) * 3600))],
            unreadCount: index.isMultiple(of: 3) ? 1 : 0,
            latestActivity: .now.addingTimeInterval(-Double(index) * 3600)
        )
    }
}

#Preview("Chats · Five conversations") { ChatsView(previewInbox: .loaded(sampleThreads(5, state: .accepted))) }
#Preview("Chats · 24 conversations · Large text") {
    ChatsView(previewInbox: .loaded(sampleThreads(24, state: .accepted))).environment(\.dynamicTypeSize, .accessibility1)
}
#Preview("Requests · Loading · Light") {
    NavigationStack { MessageRequestsView(previewLoading: true) }.preferredColorScheme(.light)
}
#Preview("Requests · Empty") { NavigationStack { MessageRequestsView(previewRequests: []) } }
#Preview("Requests · 24 in each segment") {
    NavigationStack {
        MessageRequestsView(previewRequests: sampleThreads(24, state: .pendingIncoming) + sampleThreads(24, state: .pendingOutgoing))
    }
}
#Preview("Chats · Sample inbox") { ChatsView(previewInbox: .loaded([outgoing, accepted, incoming])) }
#Preview("Chats · Multiple incoming requests") {
    let second = ChatConversation(
        participant: ChatParticipant(id: UUID(),
                                     name: "Alexandra María Fernández de la Cruz",
                                     initials: "AF", avatarURL: nil),
        state: .pendingIncoming,
        messages: [ChatMessage(id: 5, text: "Hi! Would you like to chat?", sentByMe: false, sentAt: .now)]
    )
    ChatsView(previewInbox: .loaded([incoming, second, outgoing, accepted]))
}
#Preview("Chats · Sent only") { ChatsView(previewInbox: .loaded([outgoing])) }
#Preview("Chats · Empty") { ChatsView(previewInbox: .loaded([])) }
#Preview("Chats · Loading") { ChatsView(previewInbox: .loading) }
#Preview("Chats · Error") { ChatsView(previewInbox: .failed("Check your connection and try again.")) }
#Preview("Requests · Sample") { NavigationStack { MessageRequestsView(previewRequests: [incoming, outgoing]) } }
#Preview("Conversation · Introduction") { NavigationStack { ChatConversationView(conversation: ChatConversation(participant: maya, state: .introduction), isPreview: true) } }
#Preview("Conversation · Incoming") { NavigationStack { ChatConversationView(conversation: incoming, isPreview: true) } }
#Preview("Conversation · Awaiting approval") { NavigationStack { ChatConversationView(conversation: outgoing, isPreview: true) } }
#Preview("Conversation · Accepted") { NavigationStack { ChatConversationView(conversation: accepted, isPreview: true) } }
#Preview("Conversation · Declined") { NavigationStack { ChatConversationView(conversation: ChatConversation(participant: maya, state: .declined, messages: outgoing.messages), isPreview: true) } }
#Preview("Conversation · Blocked") { NavigationStack { ChatConversationView(conversation: ChatConversation(participant: maya, state: .blocked, messages: accepted.messages), isPreview: true) } }
#Preview("Send · Enabled") {
    ChatConversationView(conversation: accepted, isPreview: true, sendState: .ready, initialDraft: "See you there!")
}
#Preview("Send · Sending") {
    ChatConversationView(conversation: accepted, isPreview: true, sendState: .sending, initialDraft: "See you there!")
}
#Preview("Send · Failed") {
    ChatConversationView(conversation: accepted, isPreview: true, sendState: .failed, initialDraft: "See you there!")
}
#Preview("Blocked Students · Empty") { BlockedStudentsView(previewStudents: []) }
#Preview("Blocked Students · Loading") { BlockedStudentsView(previewLoading: true) }
#Preview("Blocked Students · Retry") { BlockedStudentsView(previewError: "Check your connection and try again.") }
#Preview("Blocked Students · Owned blocks") {
    BlockedStudentsView(previewStudents: [maya, omar]).environment(\.dynamicTypeSize, .accessibility1)
}
#Preview("Conversation · Owned block") {
    ChatConversationView(conversation: ChatConversation(participant: maya, state: .blocked, messages: accepted.messages),
                         isPreview: true, previewOwnsBlock: true)
}
#Preview("Conversation · Read-only after unblock") {
    ChatConversationView(conversation: ChatConversation(participant: maya, state: .declined, messages: accepted.messages),
                         isPreview: true)
}
#endif
