//
//  NotificationService.swift
//  SkillSwap
//
//  Read/update access to the signed-in student's in-app notifications.
//  Mirrors supabase/phase3_notifications.sql (recipient-scoped RLS; rows are
//  created ONLY by database triggers, never by the client). This service does
//  NOT insert notifications — it can only read its own and flip is_read.
//
//  ⚠️ BACKEND PENDING: until phase3_notifications.sql is run in Supabase, the
//  `notifications` table does not exist and every fetch fails gracefully to an
//  empty list (no mock data is substituted). See DATA_SOURCES.md / report.
//

import Foundation
import Supabase

struct AppNotification: Identifiable {
    let id: String
    let type: String
    let message: String
    let exchangeID: String?
    let isRead: Bool
    let createdAt: Date?
    let actorName: String?
    let actorAvatarURL: String?

    /// Concise human title derived from the event type.
    var title: String {
        switch type {
        case "request_received":     return "New exchange request"
        case "request_accepted":     return "Request accepted"
        case "request_declined":     return "Request declined"
        case "session_proposed":     return "Session proposed"
        case "session_confirmed":    return "Session confirmed"
        case "session_cancelled":    return "Session cancelled"
        case "exchange_cancelled":   return "Exchange cancelled"
        case "completion_confirmed": return "Completion confirmed"
        case "kudos_received":       return "Kudos received"
        default:                     return "Update"
        }
    }

    /// "<Name> <message>" when an actor is known, else just the message.
    var detail: String {
        if let actorName, !actorName.isEmpty { return "\(actorName) \(message)" }
        return message
    }

    var symbol: String {
        switch type {
        case "request_received":     return "tray.and.arrow.down.fill"
        case "request_accepted":     return "checkmark.circle.fill"
        case "request_declined":     return "xmark.circle.fill"
        case "session_proposed":     return "calendar.badge.plus"
        case "session_confirmed":    return "calendar.badge.checkmark"
        case "session_cancelled":    return "calendar.badge.exclamationmark"
        case "exchange_cancelled":   return "slash.circle.fill"
        case "completion_confirmed": return "checkmark.seal.fill"
        case "kudos_received":       return "heart.fill"
        default:                     return "bell.fill"
        }
    }
}

struct NotificationService {

    private let client = SupabaseManager.client

    private let selectExpr = """
    id, type, message, exchange_id, session_id, is_read, created_at, \
    actor:profiles!actor_id ( full_name, avatar_url )
    """

    func fetch() async throws -> [AppNotification] {
        let rows: [NotificationRow] = try await client
            .from("notifications")
            .select(selectExpr)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { row in
            AppNotification(
                id: row.id, type: row.type, message: row.message,
                exchangeID: row.exchangeID, isRead: row.isRead,
                createdAt: row.createdAt.flatMap(Self.parseDate),
                actorName: row.actor?.fullName, actorAvatarURL: row.actor?.avatarURL
            )
        }
    }

    func unreadCount() async throws -> Int {
        try await fetch().filter { !$0.isRead }.count
    }

    func markRead(_ id: String) async throws {
        try await client.from("notifications")
            .update(["is_read": true])
            .eq("id", value: id)
            .execute()
    }

    func markAllRead() async throws {
        try await client.from("notifications")
            .update(["is_read": true])
            .eq("is_read", value: false)
            .execute()
    }

    nonisolated private static func parseDate(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        return f1.date(from: iso) ?? f2.date(from: iso)
    }
}

// MARK: - Decoding

private struct NotificationRow: Decodable {
    let id: String
    let type: String
    let message: String
    let exchangeID: String?
    let isRead: Bool
    let createdAt: String?
    let actor: Actor?

    struct Actor: Decodable {
        let fullName: String?
        let avatarURL: String?
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case avatarURL = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, type, message, actor
        case exchangeID = "exchange_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}
