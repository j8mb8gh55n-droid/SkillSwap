import Foundation

struct ChatParticipant {
    let id: UUID
    let name: String
    let initials: String
    let avatarURL: String?
}

struct ChatMessage: Identifiable {
    var id: Int64 = 0
    let text: String
    let sentByMe: Bool
    let sentAt: Date
}

struct ChatConversation: Identifiable {
    enum State {
        case introduction, pendingIncoming, pendingOutgoing, accepted, declined, blocked
    }

    var serverID: UUID? = nil
    var id: UUID { serverID ?? participant.id }
    let participant: ChatParticipant
    var state: State
    var messages: [ChatMessage] = []
    var canReconnect = false
    var reconnectionMessage: Int64?
    var isMuted = false
    var unreadCount: Int64 = 0
    var unread: Bool { unreadCount > 0 }
    var latestActivity: Date = .distantPast
    var exchangeContext: String? = nil

    static let declineExplanation = "If you decline, neither of you can send another introduction to the other."

    var latestMessage: ChatMessage? { messages.max { $0.id < $1.id } }
}
