//
//  ExchangeService.swift
//  SkillSwap
//
//  Read-only fetch of the signed-in student's real exchanges (+ their sessions)
//  from the existing Supabase tables. RLS restricts rows to the participant.
//  No schema/policy changes. Derives each exchange from the CURRENT user's
//  perspective (learning/teaching direction, status, next action).
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Summary model (per-user perspective)

enum ExchangeAttention { case reviewRequest, scheduleSession, reviewSession, confirmCompletion }

struct ExchangeSummary: Identifiable {
    let id: String
    var otherID: String = ""          // the other participant's profile id (kudos recipient)
    let otherName: String
    let otherMajor: String?
    let otherInitials: String
    let otherAvatarURL: String?
    var otherLocalImage: String? = nil   // ⚠️ demo/test only
    let youLearn: String
    let youTeach: String
    let status: ExchangeStatus
    let isIncoming: Bool
    let actionLabel: String
    let attention: ExchangeAttention?   // non-nil → appears in "Needs Your Attention"
    let hasConfirmedFutureSession: Bool
    var session: SessionInfo? = nil
    var youCompleted: Bool = false
    var otherCompleted: Bool = false
    let bannerColors: [Color]

    /// Build the SkillExchange used by the existing ExchangeDetailsView.
    var asExchange: SkillExchange {
        SkillExchange(
            id: id, studentName: otherName, studentMajor: otherMajor ?? "",
            initials: otherInitials, learningSkill: youLearn, offeringSkill: youTeach,
            status: status, isIncoming: isIncoming, date: "",
            bannerColors: bannerColors, imageURL: otherAvatarURL, localImageName: otherLocalImage,
            hasConfirmedSession: hasConfirmedFutureSession, session: session,
            youCompleted: youCompleted, otherCompleted: otherCompleted,
            otherID: otherID
        )
    }
}

struct ExchangeService {

    private let client = SupabaseManager.client

    private let selectExpr = """
    id, status, requester_id, recipient_id, requester_completed, recipient_completed, created_at, \
    offered_skill:skills!offered_skill_id ( name ), \
    requested_skill:skills!requested_skill_id ( name ), \
    requester:profiles!requester_id ( id, full_name, major, avatar_url ), \
    recipient:profiles!recipient_id ( id, full_name, major, avatar_url ), \
    sessions ( scheduled_at, status, proposed_by, duration_minutes, format, location_or_link )
    """

    func fetchMyExchanges() async throws -> [ExchangeSummary] {
        let me = try await client.auth.session.user.id

        let rows: [ExchangeRow] = try await client
            .from("exchanges")
            .select(selectExpr)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map { map($0, me: me) }
    }

    func fetchExchange(id: UUID) async throws -> SkillExchange? {
        let me = try await client.auth.session.user.id
        let rows: [ExchangeRow] = try await client
            .from("exchanges")
            .select(selectExpr)
            .eq("id", value: id)
            .limit(1)
            .execute().value
        return rows.first.map { map($0, me: me).asExchange }
    }

    // MARK: - Create exchange (Phase C1)

    enum ExchangeCreateError: LocalizedError {
        case selfRequest
        case duplicatePending
        case recipientUnavailable
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .selfRequest:     return "You can't request an exchange with yourself."
            case .duplicatePending: return "You already have a pending request with this student. Check Outgoing in Exchanges."
            case .recipientUnavailable: return "This student isn't accepting new exchange requests right now."
            case .rejected(let m): return m
            }
        }
    }

    /// The signed-in student's teaching skills (with catalog ids) — the skills
    /// they can OFFER in an exchange.
    func fetchMyTeachingSkills() async throws -> [CatalogSkill] {
        let me = try await client.auth.session.user.id.uuidString
        let rows: [TeachSkillRow] = try await client
            .from("student_skills")
            .select("skills ( id, name, category )")
            .eq("student_id", value: me)
            .eq("skill_type", value: "teach")
            .execute()
            .value
        return rows.compactMap { $0.skills.map { CatalogSkill(id: $0.id, name: $0.name, category: $0.category) } }
    }

    /// Inserts a real PENDING exchange. The DB trigger forces status=pending and
    /// validates that `offeredSkillID` is one the caller teaches and
    /// `requestedSkillID` is one the recipient teaches; RLS requires
    /// requester_id == auth.uid(). Duplicate pending rows are rejected by the
    /// partial unique index and surfaced as a friendly error.
    func createExchange(
        recipientID: String,
        offeredSkillID: Int,
        requestedSkillID: Int,
        message: String?,
        learningGoal: String?,
        preferredFormat: String
    ) async throws {
        let me = try await client.auth.session.user.id.uuidString
        guard me.caseInsensitiveCompare(recipientID) != .orderedSame else {
            throw ExchangeCreateError.selfRequest
        }

        let payload = ExchangeInsert(
            requester_id: me,
            recipient_id: recipientID,
            offered_skill_id: offeredSkillID,
            requested_skill_id: requestedSkillID,
            message: (message?.isEmpty == false) ? message : nil,
            learning_goal: (learningGoal?.isEmpty == false) ? learningGoal : nil,
            preferred_format: preferredFormat
        )

        do {
            try await client.from("exchanges").insert(payload).execute()
        } catch {
            let desc = String(describing: error).lowercased()
            print("[Exchange] create failed:", error)
            if desc.contains("duplicate") || desc.contains("unique") || desc.contains("23505") {
                throw ExchangeCreateError.duplicatePending
            }
            // Backend guard: recipient switched to Unavailable (D5 trigger).
            if desc.contains("not accepting new exchange requests") {
                throw ExchangeCreateError.recipientUnavailable
            }
            throw error
        }
    }

    // MARK: - Status actions (Phase C2)
    // Who-may-do-what and valid transitions are enforced by the DB
    // exchanges_guard trigger + RLS; unauthorized attempts throw.

    func accept(exchangeID: String)  async throws { try await updateStatus(exchangeID, to: "accepted") }
    func decline(exchangeID: String) async throws { try await updateStatus(exchangeID, to: "declined") }
    func cancelExchange(exchangeID: String) async throws { try await updateStatus(exchangeID, to: "cancelled") }

    private func updateStatus(_ id: String, to status: String) async throws {
        do {
            try await client.from("exchanges")
                .update(["status": status])
                .eq("id", value: id)
                .execute()
        } catch {
            print("[Exchange] status update → \(status) failed:", error)
            throw error
        }
    }

    // MARK: - Kudos (Phase D1)
    // Inserts/reads go through RLS as the authenticated user; the kudos trigger
    // enforces completed-exchange + participant rules; the UNIQUE constraint
    // prevents duplicates; counts come from the SECURITY DEFINER RPC.

    func giveKudos(exchangeID: String, recipientID: String, tags: [String], message: String?) async throws {
        let me = try await client.auth.session.user.id.uuidString
        let payload = KudosInsert(
            exchange_id: exchangeID, giver_id: me, recipient_id: recipientID,
            tags: tags, message: (message?.isEmpty == false) ? message : nil
        )
        do {
            try await client.from("kudos").insert(payload).execute()
        } catch {
            print("[Kudos] give failed:", error)
            throw error
        }
    }

    /// Whether the signed-in user already gave kudos for this exchange.
    func hasGivenKudos(exchangeID: String) async throws -> Bool {
        let me = try await client.auth.session.user.id.uuidString
        let rows: [KudosIDRow] = try await client
            .from("kudos")
            .select("id")
            .eq("exchange_id", value: exchangeID)
            .eq("giver_id", value: me)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    /// Verified aggregate kudos count for any student (via the RPC — counts only).
    func kudosCount(studentID: String) async throws -> Int {
        try await client
            .rpc("kudos_count", params: ["student": studentID])
            .execute()
            .value
    }

    /// The signed-in user's own received-kudos count (for My Profile).
    func myKudosCount() async throws -> Int {
        let me = try await client.auth.session.user.id.uuidString
        return try await kudosCount(studentID: me)
    }

    // MARK: - Verified statistics (Phase D2)
    // Aggregate, counts-only statistics for any student, via the server-side
    // public.student_stats(student) RPC. Exchanges are RLS-restricted to their
    // participants, so these numbers must come from the SECURITY DEFINER
    // function — never fabricated client-side. "Kudos Received" (total) reuses
    // the existing kudos_count() RPC above.

    /// Verified aggregate statistics for any student (counts only, via RPC).
    func studentStats(studentID: String) async throws -> StudentStats {
        try await client
            .rpc("student_stats", params: ["student": studentID])
            .execute()
            .value
    }

    /// The signed-in user's own verified statistics (for My Profile).
    func myStats() async throws -> StudentStats {
        let me = try await client.auth.session.user.id.uuidString
        return try await studentStats(studentID: me)
    }

    /// Kudos the signed-in user has received (RLS permits recipient to read).
    func receivedKudos() async throws -> [ReceivedKudos] {
        let me = try await client.auth.session.user.id.uuidString
        let rows: [KudosRow] = try await client
            .from("kudos")
            .select("id, tags, message, created_at, giver:profiles!giver_id ( full_name, avatar_url )")
            .eq("recipient_id", value: me)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { r in
            let name = (r.giver?.fullName?.isEmpty == false) ? r.giver!.fullName! : "A student"
            return ReceivedKudos(
                id: r.id, giverName: name,
                giverInitials: Self.initials(name),
                giverAvatarURL: r.giver?.avatarURL,
                tags: r.tags, message: r.message,
                createdAt: r.createdAt.flatMap(Self.parseDate)
            )
        }
    }

    // MARK: - Completion (Phase C4)
    // Each participant flips only THEIR own flag; the exchanges_guard trigger
    // requires a confirmed, already-occurred session, blocks withdrawals, and
    // flips status→completed only when BOTH flags are set. All enforced server-side.

    struct ExchangeCompletion { let status: String; let requesterCompleted: Bool; let recipientCompleted: Bool }

    func confirmCompletion(exchangeID: String, asRecipient: Bool) async throws {
        let column = asRecipient ? "recipient_completed" : "requester_completed"
        do {
            try await client.from("exchanges")
                .update([column: true])
                .eq("id", value: exchangeID)
                .execute()
        } catch {
            print("[Completion] confirm failed:", error)
            throw error
        }
    }

    func fetchCompletion(exchangeID: String) async throws -> ExchangeCompletion {
        let rows: [CompletionRow] = try await client
            .from("exchanges")
            .select("status, requester_completed, recipient_completed")
            .eq("id", value: exchangeID)
            .limit(1)
            .execute()
            .value
        guard let r = rows.first else {
            throw NSError(domain: "SkillSwap", code: 404, userInfo: [NSLocalizedDescriptionKey: "Exchange not found"])
        }
        return ExchangeCompletion(status: r.status, requesterCompleted: r.requesterCompleted, recipientCompleted: r.recipientCompleted)
    }

    // MARK: - Sessions (Phase C3)
    // Insert forces status='proposed' and proposed_by=caller (sessions trigger);
    // confirm is allowed only to the OTHER participant; cancel to either — all
    // enforced server-side. Format must be 'online' or 'in_person'.

    func proposeSession(
        exchangeID: String,
        scheduledAt: Date,
        durationMinutes: Int,
        format: String,
        locationOrLink: String?
    ) async throws {
        let me = try await client.auth.session.user.id.uuidString
        let iso = ISO8601DateFormatter().string(from: scheduledAt)
        let payload = SessionInsert(
            exchange_id: exchangeID,
            scheduled_at: iso,
            duration_minutes: durationMinutes,
            format: format,
            location_or_link: (locationOrLink?.isEmpty == false) ? locationOrLink : nil,
            proposed_by: me
        )
        do {
            try await client.from("sessions").insert(payload).execute()
        } catch {
            print("[Session] propose failed:", error)
            throw error
        }
    }

    func confirmSession(sessionID: String) async throws { try await updateSession(sessionID, to: "confirmed") }
    func cancelSession(sessionID: String) async throws  { try await updateSession(sessionID, to: "cancelled") }

    private func updateSession(_ id: String, to status: String) async throws {
        do {
            try await client.from("sessions").update(["status": status]).eq("id", value: id).execute()
        } catch {
            print("[Session] update → \(status) failed:", error)
            throw error
        }
    }

    /// The current relevant session for an exchange (newest non-cancelled),
    /// including its id + whether the signed-in user proposed it.
    func fetchCurrentSession(exchangeID: String) async throws -> SessionInfo? {
        let me = try await client.auth.session.user.id
        let rows: [SessionFullRow] = try await client
            .from("sessions")
            .select("id, scheduled_at, duration_minutes, format, location_or_link, status, proposed_by, created_at")
            .eq("exchange_id", value: exchangeID)
            .order("created_at", ascending: false)
            .execute()
            .value

        guard let s = rows.first(where: { $0.status != "cancelled" }) else { return nil }
        return SessionInfo(
            id: s.id,
            scheduledAt: s.scheduledAt.flatMap(Self.parseDate),
            durationMinutes: s.durationMinutes ?? 60,
            format: s.format == "in_person" ? "In Person" : "Online",
            locationOrLink: s.locationOrLink,
            status: s.status,
            proposedByMe: s.proposedBy == me
        )
    }

    // MARK: - Mapping

    private func map(_ r: ExchangeRow, me: UUID) -> ExchangeSummary {
        let isRequester = (r.requester.id == me)
        let other = isRequester ? r.recipient : r.requester
        let name = (other.fullName?.isEmpty == false) ? other.fullName! : "A student"

        // Direction from this user's perspective.
        let youLearn = (isRequester ? r.requestedSkill?.name : r.offeredSkill?.name) ?? "—"
        let youTeach = (isRequester ? r.offeredSkill?.name : r.requestedSkill?.name) ?? "—"
        let myCompleted = isRequester ? r.requesterCompleted : r.recipientCompleted
        let otherCompletedFlag = isRequester ? r.recipientCompleted : r.requesterCompleted
        let status = Self.status(r.status)
        let isIncoming = !isRequester

        // Session state.
        let now = Date()
        let sessions = r.sessions ?? []
        func date(_ s: String?) -> Date? { s.flatMap(Self.parseDate) }
        let confirmed = sessions.filter { $0.status == "confirmed" }
        let hasConfirmedFuture = confirmed.contains { (date($0.scheduledAt) ?? .distantPast) > now }
        let hasConfirmedPast   = confirmed.contains { (date($0.scheduledAt) ?? .distantFuture) <= now }
        let proposedForMe = sessions.contains { $0.status == "proposed" && $0.proposedBy != me }
        let proposedByMe  = sessions.contains { $0.status == "proposed" && $0.proposedBy == me }
        let hasActiveSession = sessions.contains { $0.status == "proposed" || $0.status == "confirmed" }

        // Current relevant session: a confirmed one (prefer the soonest future,
        // else the latest), otherwise the most recent proposed one.
        let chosen: SessionRow? = confirmed
            .sorted { (date($0.scheduledAt) ?? .distantPast) > (date($1.scheduledAt) ?? .distantPast) }
            .first
            ?? sessions.first { $0.status == "proposed" }
        let sessionInfo: SessionInfo? = chosen.map { s in
            SessionInfo(
                scheduledAt: date(s.scheduledAt),
                durationMinutes: s.durationMinutes ?? 60,
                format: (s.format == "in_person") ? "In Person" : "Online",
                locationOrLink: s.locationOrLink,
                status: s.status,
                proposedByMe: s.proposedBy == me
            )
        }

        var action = "View Details"
        var attention: ExchangeAttention? = nil

        switch status {
        case .pending:
            if isIncoming { action = "Review Request"; attention = .reviewRequest }
            else { action = "Awaiting Response" }
        case .accepted:
            if proposedForMe { action = "Review Session"; attention = .reviewSession }
            else if hasConfirmedPast && !myCompleted { action = "Confirm Completion"; attention = .confirmCompletion }
            else if hasConfirmedFuture { action = "View Session" }
            else if proposedByMe { action = "Awaiting Confirmation" }
            else if !hasActiveSession { action = "Schedule Session"; attention = .scheduleSession }
            else { action = "View Details" }
        case .completed: action = "View Details"
        case .declined, .cancelled: action = "View Details"
        }

        let seed = r.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }

        return ExchangeSummary(
            id: r.id,
            otherID: other.id.uuidString,
            otherName: name,
            otherMajor: (other.major?.isEmpty == false) ? other.major : nil,
            otherInitials: Self.initials(name),
            otherAvatarURL: other.avatarURL,
            youLearn: youLearn,
            youTeach: youTeach,
            status: status,
            isIncoming: isIncoming,
            actionLabel: action,
            attention: attention,
            hasConfirmedFutureSession: hasConfirmedFuture,
            session: sessionInfo,
            youCompleted: myCompleted,
            otherCompleted: otherCompletedFlag,
            bannerColors: HomeGradients.studentPair(seed)
        )
    }

    // MARK: - Helpers

    private static func status(_ s: String) -> ExchangeStatus {
        switch s {
        case "accepted":  return .accepted
        case "completed": return .completed
        case "declined":  return .declined
        case "cancelled": return .cancelled
        default:          return .pending
        }
    }

    private static func initials(_ name: String) -> String {
        let s = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    nonisolated private static func parseDate(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        return f1.date(from: iso) ?? f2.date(from: iso)
    }
}

// MARK: - Decoding

private struct ExchangeRow: Decodable {
    let id: String
    let status: String
    let requesterCompleted: Bool
    let recipientCompleted: Bool
    let offeredSkill: SkillNameRow?
    let requestedSkill: SkillNameRow?
    let requester: ProfileRow
    let recipient: ProfileRow
    let sessions: [SessionRow]?

    enum CodingKeys: String, CodingKey {
        case id, status, requester, recipient, sessions
        case requesterCompleted = "requester_completed"
        case recipientCompleted = "recipient_completed"
        case offeredSkill = "offered_skill"
        case requestedSkill = "requested_skill"
    }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let fullName: String?
    let major: String?
    let avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case major
        case avatarURL = "avatar_url"
    }
}

private struct SkillNameRow: Decodable { let name: String }

// Phase C1 — create payload + my-teach-skills decode.
private struct ExchangeInsert: Encodable {
    let requester_id: String
    let recipient_id: String
    let offered_skill_id: Int
    let requested_skill_id: Int
    let message: String?
    let learning_goal: String?
    let preferred_format: String
}

private struct TeachSkillRow: Decodable {
    let skills: CatalogRow?
    struct CatalogRow: Decodable { let id: Int; let name: String; let category: String }
}

// Phase D2 — verified statistics (decoded from the student_stats RPC jsonb).
struct StudentStats: Decodable {
    let completedSwaps: Int
    let skillsShared: Int
    let studentsHelped: Int
    let skillsExplored: Int
    let kudosDistinctGivers: Int

    enum CodingKeys: String, CodingKey {
        case completedSwaps      = "completed_swaps"
        case skillsShared        = "skills_shared"
        case studentsHelped      = "students_helped"
        case skillsExplored      = "skills_explored"
        case kudosDistinctGivers = "kudos_distinct_givers"
    }

    static let zero = StudentStats(
        completedSwaps: 0, skillsShared: 0, studentsHelped: 0,
        skillsExplored: 0, kudosDistinctGivers: 0
    )

    /// True when the student has no verified activity yet.
    var isEmpty: Bool {
        completedSwaps == 0 && skillsShared == 0 && studentsHelped == 0
            && skillsExplored == 0 && kudosDistinctGivers == 0
    }
}

// Phase D1 — kudos.
struct ReceivedKudos: Identifiable {
    let id: String
    let giverName: String
    let giverInitials: String
    let giverAvatarURL: String?
    let tags: [String]
    let message: String?
    let createdAt: Date?
}

private struct KudosInsert: Encodable {
    let exchange_id: String
    let giver_id: String
    let recipient_id: String
    let tags: [String]
    let message: String?
}

private struct KudosIDRow: Decodable { let id: String }

private struct KudosRow: Decodable {
    let id: String
    let tags: [String]
    let message: String?
    let createdAt: String?
    let giver: GiverRow?
    struct GiverRow: Decodable {
        let fullName: String?
        let avatarURL: String?
        enum CodingKeys: String, CodingKey { case fullName = "full_name"; case avatarURL = "avatar_url" }
    }
    enum CodingKeys: String, CodingKey { case id, tags, message, giver; case createdAt = "created_at" }
}

// Phase C4 — completion flags decode.
private struct CompletionRow: Decodable {
    let status: String
    let requesterCompleted: Bool
    let recipientCompleted: Bool
    enum CodingKeys: String, CodingKey {
        case status
        case requesterCompleted = "requester_completed"
        case recipientCompleted = "recipient_completed"
    }
}

// Phase C3 — session insert payload + full decode.
private struct SessionInsert: Encodable {
    let exchange_id: String
    let scheduled_at: String
    let duration_minutes: Int
    let format: String
    let location_or_link: String?
    let proposed_by: String
}

private struct SessionFullRow: Decodable {
    let id: String
    let scheduledAt: String?
    let durationMinutes: Int?
    let format: String
    let locationOrLink: String?
    let status: String
    let proposedBy: UUID?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, format, status
        case scheduledAt = "scheduled_at"
        case durationMinutes = "duration_minutes"
        case locationOrLink = "location_or_link"
        case proposedBy = "proposed_by"
        case createdAt = "created_at"
    }
}

private struct SessionRow: Decodable {
    let scheduledAt: String?
    let status: String
    let proposedBy: UUID?
    let durationMinutes: Int?
    let format: String?
    let locationOrLink: String?
    enum CodingKeys: String, CodingKey {
        case status, format
        case scheduledAt = "scheduled_at"
        case proposedBy = "proposed_by"
        case durationMinutes = "duration_minutes"
        case locationOrLink = "location_or_link"
    }
}
