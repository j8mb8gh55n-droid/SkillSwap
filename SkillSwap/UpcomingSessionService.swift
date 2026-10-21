//
//  UpcomingSessionService.swift
//  SkillSwap
//
//  Read-only fetch of the signed-in student's next genuinely confirmed upcoming
//  session, from the existing Supabase exchanges + sessions tables. RLS already
//  restricts rows to the authenticated participant. No schema changes.
//

import Foundation
import SwiftUI
import Supabase

struct UpcomingSessionService {

    private let client = SupabaseManager.client

    // Nested select: session → its exchange → both participant profiles + the
    // requested skill name. FK column hints disambiguate the two profile embeds.
    private let selectExpr = """
    scheduled_at, format, \
    exchanges!inner ( \
        id, status, requester_id, recipient_id, \
        requested_skill:skills!requested_skill_id ( name ), \
        requester:profiles!requester_id ( id, full_name, avatar_url ), \
        recipient:profiles!recipient_id ( id, full_name, avatar_url ) \
    )
    """

    /// The soonest confirmed, not-yet-past session on an accepted exchange the
    /// user is part of. Returns nil when there is none.
    func fetchNextUpcoming() async throws -> UpcomingSession? {

        let me = try await client.auth.session.user.id
        let nowISO = ISO8601DateFormatter().string(from: Date())

        let rows: [UpcomingRow] = try await client
            .from("sessions")
            .select(selectExpr)
            .eq("status", value: "confirmed")
            .eq("exchanges.status", value: "accepted")
            .gte("scheduled_at", value: nowISO)
            .order("scheduled_at", ascending: true)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        let e = row.exchange
        let other = (e.requester.id == me) ? e.recipient : e.requester
        let name = (other.fullName?.isEmpty == false) ? other.fullName! : "A student"

        return UpcomingSession(
            exchangeID: e.id,
            skill: e.requestedSkill?.name ?? "Skill exchange",
            partnerName: name,
            partnerInitials: Self.initials(name),
            partnerImageURL: other.avatarURL,
            partnerLocalImage: nil,
            whenText: Self.formatWhen(row.scheduledAt),
            format: Self.displayFormat(row.format),
            bannerColors: [Theme.brightLavender, Theme.powderBlue]
        )
    }

    // MARK: - Helpers

    private static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = parts.map(String.init).joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    private static func displayFormat(_ raw: String?) -> String? {
        switch raw {
        case "online":    return "Online"
        case "in_person": return "In Person"
        default:          return nil
        }
    }

    private static func formatWhen(_ iso: String) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let date = withFraction.date(from: iso) ?? plain.date(from: iso) ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Decoding

private struct UpcomingRow: Decodable {
    let scheduledAt: String
    let format: String?
    let exchange: ExchangeEmbed
    enum CodingKeys: String, CodingKey {
        case scheduledAt = "scheduled_at"
        case format
        case exchange = "exchanges"
    }
}

private struct ExchangeEmbed: Decodable {
    let id: String
    let requester: ProfileEmbed
    let recipient: ProfileEmbed
    let requestedSkill: SkillNameEmbed?
    enum CodingKeys: String, CodingKey {
        case id, requester, recipient
        case requestedSkill = "requested_skill"
    }
}

private struct ProfileEmbed: Decodable {
    let id: UUID
    let fullName: String?
    let avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}

private struct SkillNameEmbed: Decodable { let name: String }
