import Foundation
import Supabase

struct MessagingService {
    private var client: SupabaseClient { SupabaseManager.client }
    static let pageSize = 40

    private struct Thread: Decodable {
        let id: UUID
        let initiator_id: UUID
        let recipient_id: UUID
        let status: String
        let latest_activity_at: Date
        let initiator: Participant?
        let recipient: Participant?
        let latest: [Message]?
        let can_reconnect: Bool?
        let reconnection_requester: UUID?
        let reconnection_message: Int64?

        func conversation(for user: UUID, fallback: ChatParticipant? = nil) throws -> ChatConversation {
            let outgoing = initiator_id == user
            let otherID = outgoing ? recipient_id : initiator_id
            let profile = outgoing ? recipient : initiator
            let state: ChatConversation.State
            switch status {
            case "pending": state = (reconnection_requester ?? initiator_id) == user ? .pendingOutgoing : .pendingIncoming
            case "accepted": state = .accepted
            case "declined": state = .declined
            case "blocked": state = .blocked
            default: throw MessagingError.invalidResponse
            }
            let name = profile?.full_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let participant = if let name, !name.isEmpty {
                ChatParticipant(id: otherID, name: name,
                                initials: name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased(),
                                avatarURL: profile?.avatar_url)
            } else if let fallback, fallback.id == otherID {
                fallback
            } else {
                ChatParticipant(id: otherID, name: "Student", initials: "?", avatarURL: profile?.avatar_url)
            }
            return ChatConversation(serverID: id, participant: participant, state: state,
                                    messages: latest?.map { $0.model(for: user) } ?? [],
                                    canReconnect: can_reconnect == true, reconnectionMessage: reconnection_message,
                                    latestActivity: latest_activity_at)
        }
    }

    private struct Participant: Decodable {
        let full_name: String?
        let avatar_url: String?
    }

    private struct Message: Decodable {
        let id: Int64
        let author_id: UUID
        let body: String
        let created_at: Date

        func model(for user: UUID) -> ChatMessage {
            ChatMessage(id: id, text: body, sentByMe: author_id == user, sentAt: created_at)
        }
    }

    private struct Unread: Decodable {
        let conversation_id: UUID
        let unread_count: Int64
    }

    private let columns = """
        id,initiator_id,recipient_id,status,latest_activity_at,
        initiator:profiles!chat_conversations_initiator_id_fkey(full_name,avatar_url),
        recipient:profiles!chat_conversations_recipient_id_fkey(full_name,avatar_url)
        """

    private func userID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    private func threadPage(_ scope: String, offset: Int = 0, limit: Int = 40, student: UUID? = nil) async throws -> [Thread]? {
        struct Parameters: Encodable {
            let p_scope: String
            let p_offset: Int
            let p_limit: Int
            let p_student: UUID?
        }

        do {
            return try await client.rpc("chat_threads", params: Parameters(
                p_scope: scope, p_offset: offset, p_limit: limit, p_student: student
            )).execute().value
        } catch let error as PostgrestError where error.code == "PGRST202" {
            return nil
        }
    }

    func inbox() async throws -> [ChatConversation] {
        let user = try await userID()
        let counts: [Unread] = try await client.rpc("chat_unread_counts").execute().value
        let unread = Dictionary(uniqueKeysWithValues: counts.map { ($0.conversation_id, $0.unread_count) })
        var result: [ChatConversation] = []
        let batch = 100
        while true {
            guard let rows = try await threadPage("inbox", offset: result.count, limit: batch) else {
                throw MessagingError.inboxUnavailable
            }
            let muted = try await mutedConversations(for: user, in: rows.map(\.id))
            result += try rows.map {
                var conversation = try $0.conversation(for: user)
                conversation.unreadCount = unread[$0.id] ?? 0
                conversation.isMuted = muted.contains($0.id)
                return conversation
            }
            if rows.count < batch { break }
        }
        var seen = Set<UUID>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func mutedConversations(for user: UUID, in ids: [UUID]) async throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        struct Preference: Decodable { let conversation_id: UUID }
        let rows: [Preference] = try await client.from("chat_conversation_preferences")
            .select("conversation_id")
            .eq("student_id", value: user)
            .eq("muted", value: true)
            .in("conversation_id", values: ids)
            .execute().value
        return Set(rows.map(\.conversation_id))
    }

    func setMuted(_ muted: Bool, in conversation: UUID) async throws {
        struct Parameters: Encodable { let p_conversation: UUID; let p_muted: Bool }
        try await client.rpc("chat_set_muted", params: Parameters(p_conversation: conversation, p_muted: muted)).execute()
    }

    func hide(conversation: UUID) async throws {
        struct Parameters: Encodable { let p_conversation: UUID }
        try await client.rpc("chat_hide", params: Parameters(p_conversation: conversation)).execute()
    }

    func requests(received: Bool, offset: Int, limit: Int) async throws -> [ChatConversation] {
        let user = try await userID()
        let scope = received ? "received" : "sent"
        if var rows = try await threadPage(scope, offset: offset, limit: min(limit, 100)) {
            while rows.count < limit && rows.count.isMultiple(of: 100) {
                let count = min(limit - rows.count, 100)
                guard let next = try await threadPage(scope, offset: offset + rows.count, limit: count) else {
                    throw MessagingError.unavailable
                }
                rows += next
                if next.count < count { break }
            }
            return try rows.map { try $0.conversation(for: user) }
        }
        let rows: [Thread] = try await client.from("chat_conversations")
            .select(columns + ",latest:chat_messages(id,author_id,body,created_at)")
            .eq("status", value: "pending")
            .eq(received ? "recipient_id" : "initiator_id", value: user)
            .order("latest_activity_at", ascending: false)
            .order("id", ascending: false)
            .order("id", ascending: false, referencedTable: "latest")
            .limit(1, referencedTable: "latest")
            .range(from: offset, to: offset + limit - 1)
            .execute().value
        return try rows.map { try $0.conversation(for: user) }
    }

    func conversation(for participant: ChatParticipant, id: UUID?) async throws -> ChatConversation {
        let user = try await userID()
        if let rows = try await threadPage("thread", limit: 1, student: participant.id) {
            if let row = rows.first, id == nil || id == row.id {
                return try row.conversation(for: user, fallback: participant)
            }
            if id != nil { throw MessagingError.unavailable }
            return ChatConversation(participant: participant, state: .introduction)
        }
        let query = client.from("chat_conversations").select(columns)
        if let id {
            query.eq("id", value: id)
        } else {
            let other = participant.id.uuidString
            query.or("and(initiator_id.eq.\(user),recipient_id.eq.\(other)),and(initiator_id.eq.\(other),recipient_id.eq.\(user))")
        }
        let rows: [Thread] = try await query.limit(1).execute().value
        if let row = rows.first { return try row.conversation(for: user, fallback: participant) }
        if id != nil { throw MessagingError.unavailable }
        return ChatConversation(participant: participant, state: .introduction)
    }

    func messages(in conversation: UUID, before: Int64? = nil, after: Int64? = nil) async throws -> [ChatMessage] {
        let user = try await userID()
        let query = client.from("chat_messages").select("id,author_id,body,created_at")
            .eq("conversation_id", value: conversation)
        if let before { query.lt("id", value: String(before)) }
        if let after { query.gt("id", value: String(after)) }
        let rows: [Message] = try await query.order("id", ascending: after != nil)
            .limit(Self.pageSize).execute().value
        return rows.map { $0.model(for: user) }
    }

    func introduce(to recipient: UUID, body: String) async throws -> UUID {
        struct Parameters: Encodable { let p_recipient: UUID; let p_body: String }
        return try await client.rpc("chat_introduce", params: Parameters(p_recipient: recipient, p_body: body))
            .execute().value
    }

    func respond(to conversation: UUID, accept: Bool) async throws {
        struct Parameters: Encodable { let p_conversation: UUID; let p_accept: Bool }
        try await client.rpc("chat_respond", params: Parameters(p_conversation: conversation, p_accept: accept)).execute()
    }

    func reconnect(to conversation: UUID, body: String) async throws -> Int64 {
        struct Parameters: Encodable { let p_conversation: UUID; let p_body: String }
        return try await client.rpc("chat_reconnect", params: Parameters(p_conversation: conversation, p_body: body))
            .execute().value
    }

    func respondToReconnection(in conversation: UUID, message: Int64, accept: Bool) async throws {
        struct Parameters: Encodable { let p_conversation: UUID; let p_message: Int64; let p_accept: Bool }
        try await client.rpc("chat_respond_to_reconnection",
                             params: Parameters(p_conversation: conversation, p_message: message, p_accept: accept)).execute()
    }

    func send(to conversation: UUID, body: String) async throws -> Int64 {
        struct Parameters: Encodable { let p_conversation: UUID; let p_body: String }
        return try await client.rpc("chat_send", params: Parameters(p_conversation: conversation, p_body: body))
            .execute().value
    }

    private struct OwnedBlock: Decodable {
        let student_id: UUID
        let student: Participant?
    }

    func blockedStudents() async throws -> [ChatParticipant] {
        let user = try await userID()
        var students: [ChatParticipant] = []
        let pageSize = 100
        while true {
            let rows: [OwnedBlock] = try await client.from("chat_student_blocks")
                .select("student_id,student:profiles!chat_student_blocks_student_id_fkey(full_name,avatar_url)")
                .eq("blocker_id", value: user)
                .order("student_id")
                .range(from: students.count, to: students.count + pageSize - 1)
                .execute().value
            students += rows.map { row in
                let name = row.student?.full_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Student"
                let initials = displayName.split(whereSeparator: \.isWhitespace).prefix(2)
                    .compactMap(\.first).map(String.init).joined().uppercased()
                return ChatParticipant(id: row.student_id, name: displayName,
                                       initials: initials, avatarURL: row.student?.avatar_url)
            }
            if rows.count < pageSize { return students.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        }
    }

    func ownsBlock(on student: UUID) async throws -> Bool {
        let user = try await userID()
        let rows: [OwnedBlock] = try await client.from("chat_student_blocks")
            .select("student_id")
            .eq("blocker_id", value: user)
            .eq("student_id", value: student)
            .limit(1)
            .execute().value
        return !rows.isEmpty
    }

    func block(student: UUID) async throws {
        struct Parameters: Encodable { let p_student: UUID }
        try await client.rpc("chat_block", params: Parameters(p_student: student)).execute()
    }

    func unblock(student: UUID) async throws {
        struct Parameters: Encodable { let p_student: UUID }
        try await client.rpc("chat_unblock", params: Parameters(p_student: student)).execute()
    }

    func report(conversation: UUID, reason: String, message: Int64?, details: String) async throws {
        struct Parameters: Encodable {
            let p_conversation: UUID
            let p_reason: String
            let p_message: Int64?
            let p_details: String
        }
        let _: UUID = try await client.rpc("chat_report", params: Parameters(
            p_conversation: conversation, p_reason: reason, p_message: message, p_details: details
        )).execute().value
    }

    static func reportErrorText(for error: Error) -> String {
        switch (error as? PostgrestError)?.code {
        case "23505": return "You’ve already reported this conversation or selected message."
        case "P0001": return "You’ve reached the reporting limit. Try again later."
        case "PGRST202": return "Reporting is currently unavailable."
        case "23514", "23502": return "Choose a valid reason and keep details within 500 characters."
        default: return MessagingError.text(for: error)
        }
    }

    func markRead(in conversation: UUID, through message: Int64) async throws {
        struct Parameters: Encodable { let p_conversation: UUID; let p_message: Int64 }
        try await client.rpc("chat_mark_read", params: Parameters(p_conversation: conversation, p_message: message)).execute()
    }
}

enum MessagingError: Error {
    case invalidResponse, unavailable, inboxUnavailable

    static func cancelled(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func text(for error: Error) -> String {
        if case MessagingError.inboxUnavailable = error {
            return "The chat inbox is temporarily unavailable. Please try again."
        }
        if error is URLError { return "Check your connection and try again." }
        switch (error as? PostgrestError)?.code {
        case "55000": return "This action is no longer available. Refresh the conversation and try again."
        case "23514", "22023": return "Check your message and try again."
        case "PGRST301", "PGRST303", "42501": return "Your session may have expired. Reopen Chats or sign in again."
        default:
            if error is AuthError { return "Sign in again to use messaging." }
            return "Messaging couldn’t complete this request. Try again."
        }
    }
}
