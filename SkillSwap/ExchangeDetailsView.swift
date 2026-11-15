//
//  ExchangeDetailsView.swift
//  SkillSwap
//
//  Redesigned: blurred profile-header based on the OTHER student's photo,
//  one cohesive Skill Swap section, a conditional Session section, contextual
//  actions derived from the exchange + session state, and a 3-dot menu for a
//  confirmed session (View / Propose Reschedule / Cancel). "What's Next?" was
//  removed — status + the available action communicate it.
//
//  NOTE: session/completion/cancellation writes are NOT wired to Supabase this
//  pass; this screen is a local simulation (consistent with the rest of the
//  app right now). Actions update local state only. Reschedule deliberately
//  does NOT replace the authoritative confirmed session (it records a pending
//  proposal), matching the backend rule that the other student must approve.
//

import SwiftUI

// MARK: - Exchange Status

enum ExchangeStatus: String, CaseIterable {
    case pending = "Pending"
    case accepted = "Accepted"
    case completed = "Completed"
    case declined = "Declined"
    case cancelled = "Cancelled"

    var color: Color {
        switch self {
        case .pending:   return Color(red: 1.0, green: 0.88, blue: 0.67)
        case .accepted:  return Color(red: 0.77, green: 0.91, blue: 0.81)
        case .completed: return Color(red: 0.72, green: 0.86, blue: 0.76)
        case .declined:  return Color(red: 1.0, green: 0.81, blue: 0.81)
        case .cancelled: return Color(red: 0.88, green: 0.88, blue: 0.90)
        }
    }

    var symbol: String {
        switch self {
        case .pending: "clock"
        case .accepted: "checkmark.circle"
        case .completed: "checkmark.seal"
        case .declined: "xmark.circle"
        case .cancelled: "slash.circle"
        }
    }
}

// MARK: - Session info (the current relevant session for an exchange)

struct SessionInfo {
    var id: String? = nil
    var scheduledAt: Date?
    var durationMinutes: Int = 60
    var format: String = "Online"          // "Online" / "In Person"
    var locationOrLink: String?
    var status: String = "confirmed"       // "proposed" / "confirmed" / "cancelled"
    var proposedByMe: Bool = true
}

// MARK: - Exchange Model

struct SkillExchange: Identifiable, Hashable {

    static func == (lhs: SkillExchange, rhs: SkillExchange) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String
    let studentName: String
    let studentMajor: String
    let initials: String
    let learningSkill: String
    let offeringSkill: String
    var status: ExchangeStatus
    let isIncoming: Bool
    let date: String
    let bannerColors: [Color]
    /// Real profile image URL when available; nil → initials fallback.
    var imageURL: String? = nil
    /// ⚠️ TEMP TEST ONLY — bundled asset name. Remove to revert.
    var localImageName: String? = nil
    /// Carried from the list so details reflect a confirmed future session
    /// (so a scheduled exchange never shows "Schedule Session").
    var hasConfirmedSession: Bool = false
    /// The current relevant session (confirmed or proposed), when one exists.
    var session: SessionInfo? = nil
    /// Two-party completion flags from this user's perspective (Phase C4).
    var youCompleted: Bool = false
    var otherCompleted: Bool = false
    /// The other participant's profile id (kudos recipient — Phase D1).
    var otherID: String = ""
}

// MARK: - Exchange Details View

struct ExchangeDetailsView: View {

    @Binding var exchange: SkillExchange
    @Environment(\.dismiss) private var dismiss

    // Local simulation overlay (no Supabase writes this pass). `session` is
    // seeded from the real exchange.session, then mutated by local actions.
    private enum SessionPhase { case none, proposed, confirmed, cancelled }
    @State private var session: SessionInfo?
    @State private var rescheduleProposed = false
    @State private var didSeed = false

    // Real two-party completion flags (Phase C4).
    @State private var youCompleted = false
    @State private var otherCompleted = false

    @State private var showDeclineConfirmation = false
    @State private var showCancelSession = false
    @State private var showCancelExchange = false
    @State private var showKudos = false
    @State private var kudosGiven = false    // Phase D1 — already sent?

    // Real exchange-level actions (Phase C2).
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showSchedule = false       // Phase C3
    private let exchangeService = ExchangeService()

    /// Runs a real session write, then reloads the current session.
    private func sessionAction(_ op: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                try await op()
                await loadSession()
                isWorking = false
            } catch {
                isWorking = false
                print("[Session] action failed:", error)
                actionError = "That action couldn't be completed. Please try again."
            }
        }
    }

    /// Loads the current real session for this exchange (accepted only).
    private func loadSession() async {
        guard exchange.status == .accepted else { return }
        if let s = try? await exchangeService.fetchCurrentSession(exchangeID: exchange.id) {
            withAnimation { session = s }
        } else {
            withAnimation { session = nil }
        }
    }

    /// Whether the signed-in user already gave kudos for this completed exchange.
    private func loadKudosGiven() async {
        guard exchange.status == .completed else { return }
        kudosGiven = (try? await exchangeService.hasGivenKudos(exchangeID: exchange.id)) ?? false
    }

    /// Loads the real completion flags (and flips to completed if both confirmed).
    private func loadCompletion() async {
        guard exchange.status == .accepted else { return }
        if let c = try? await exchangeService.fetchCompletion(exchangeID: exchange.id) {
            withAnimation {
                youCompleted = exchange.isIncoming ? c.recipientCompleted : c.requesterCompleted
                otherCompleted = exchange.isIncoming ? c.requesterCompleted : c.recipientCompleted
                if c.status == "completed" { exchange.status = .completed }
            }
        }
    }

    /// Confirms THIS user's completion (server flips to completed only when both do).
    private func confirmCompletionAction() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                try await exchangeService.confirmCompletion(exchangeID: exchange.id, asRecipient: exchange.isIncoming)
                await loadCompletion()
                isWorking = false
            } catch {
                isWorking = false
                print("[Completion] confirm failed:", error)
                actionError = "That action couldn't be completed. Please try again."
            }
        }
    }

    private var firstName: String {
        exchange.studentName.components(separatedBy: " ").first ?? exchange.studentName
    }

    /// Runs a real Supabase status action, then updates local state / dismisses.
    /// The DB trigger + RLS enforce authorization; failures surface an alert.
    private func perform(_ op: @escaping () async throws -> Void,
                         setStatus newStatus: ExchangeStatus?,
                         dismissAfter: Bool) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                try await op()
                isWorking = false
                if let newStatus { withAnimation { exchange.status = newStatus } }
                if dismissAfter { dismiss() }
            } catch {
                isWorking = false
                print("[ExchangeDetails] action failed:", error)
                actionError = "That action couldn't be completed. Please try again."
            }
        }
    }

    // MARK: - Session phase (derived from the current session)

    private var sessionPhase: SessionPhase {
        guard let s = session else { return .none }
        switch s.status {
        case "proposed":  return .proposed
        case "confirmed": return .confirmed
        case "cancelled": return .cancelled
        default:          return .none
        }
    }
    private var sessionIsFuture: Bool {
        guard let d = session?.scheduledAt else { return true }
        return d > Date()
    }
    private var proposedByMe: Bool { session?.proposedByMe ?? true }

    // MARK: - Derived contextual action

    private enum PrimaryAction {
        case acceptDecline, awaitingResponse, schedule, awaitingConfirmation
        case reviewSession, confirmCompletion, none
    }

    private var eligibleForCompletion: Bool {
        exchange.status == .accepted && sessionPhase == .confirmed && !sessionIsFuture
    }

    private var primaryAction: PrimaryAction {
        switch exchange.status {
        case .pending:
            return exchange.isIncoming ? .acceptDecline : .awaitingResponse
        case .declined, .cancelled, .completed:
            return .none
        case .accepted:
            switch sessionPhase {
            case .none, .cancelled: return .schedule
            case .proposed:         return proposedByMe ? .awaitingConfirmation : .reviewSession
            case .confirmed:        return eligibleForCompletion ? .confirmCompletion : .none
            }
        }
    }

    private var showSessionSection: Bool { sessionPhase != .none }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.warmIvory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader

                    VStack(alignment: .leading, spacing: 22) {
                        skillSwapSection
                        if showSessionSection { sessionSection }
                        if eligibleForCompletion { completionSection }
                        if exchange.status == .completed { completedSummary; kudosSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .bottom) { primaryActionBar }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { seedIfNeeded(); Task { await loadSession(); await loadCompletion(); await loadKudosGiven() } }
        .navigationDestination(isPresented: $showSchedule) { scheduleDestination }
        .confirmationDialog("Decline this exchange?", isPresented: $showDeclineConfirmation, titleVisibility: .visible) {
            Button("Decline Exchange", role: .destructive) {
                perform({ try await exchangeService.decline(exchangeID: exchange.id) }, setStatus: .declined, dismissAfter: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the exchange as declined.")
        }
        .confirmationDialog("Cancel this session?", isPresented: $showCancelSession, titleVisibility: .visible) {
            Button("Cancel Session", role: .destructive) {
                if let sid = session?.id {
                    sessionAction { try await exchangeService.cancelSession(sessionID: sid) }
                }
            }
            Button("Keep Session", role: .cancel) {}
        } message: {
            Text("The other student will be notified. Your exchange will remain active so you can schedule another session.")
        }
        .confirmationDialog("Cancel this exchange?", isPresented: $showCancelExchange, titleVisibility: .visible) {
            Button("Cancel Exchange", role: .destructive) {
                perform({ try await exchangeService.cancelExchange(exchangeID: exchange.id) }, setStatus: .cancelled, dismissAfter: true)
            }
            Button("Keep Exchange", role: .cancel) {}
        } message: {
            Text("This ends the skill-exchange arrangement with \(firstName). Any scheduled session will be cancelled. This cannot be undone.")
        }
        .sheet(isPresented: $showKudos) {
            NavigationStack {
                KudosView(partnerName: firstName, exchangeID: exchange.id, recipientID: exchange.otherID,
                          onSent: { kudosGiven = true })
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Please try again.")
        }
    }

    private var scheduleDestination: some View {
        ScheduleSessionView(
            studentName: exchange.studentName, studentMajor: exchange.studentMajor,
            studentInitials: exchange.initials, learningSkill: exchange.learningSkill,
            bannerColors: exchange.bannerColors,
            exchangeID: exchange.id,
            onProposed: { Task { await loadSession() } }
        )
    }

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        youCompleted = exchange.youCompleted
        otherCompleted = exchange.otherCompleted
        // Prefer the real session carried from the list; fall back to the
        // confirmed-future flag when only that was available.
        if let real = exchange.session {
            session = real
        } else if exchange.status == .accepted && exchange.hasConfirmedSession {
            session = SessionInfo(scheduledAt: nil, status: "confirmed", proposedByMe: false)
        }
    }

    // MARK: - Profile header (blurred photo → ivory)

    private var profileHeader: some View {
        ZStack(alignment: .topLeading) {
            headerVisual
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Back + status, top row.
            HStack {
                Button { dismiss() } label: {
                    BackChevron().foregroundStyle(Theme.charcoal)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                HStack(spacing: 8) {
                    statusChip
                    if hasHeaderMenu { headerMenu }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            // Identity (tappable → the other student's public profile).
            NavigationLink { otherStudentProfile } label: {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exchange.studentName)
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.charcoal)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if !exchange.studentMajor.isEmpty {
                            Text(exchange.studentMajor)
                                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone).lineLimit(1)
                        }
                        Text("View profile")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedStone)
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 4)
        }
        .frame(height: 280)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: exchange.status.symbol).font(.system(size: 11, weight: .semibold))
            Text(statusLabel).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Theme.onPastel)   // fixed-dark: the chip fill is a solid light pastel in both modes
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(exchange.status.color.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
    }

    private var statusLabel: String {
        if exchange.status == .accepted && sessionPhase == .confirmed && sessionIsFuture { return "Scheduled" }
        return exchange.status.rawValue
    }

    // MARK: - Header menu (glass, contextual)

    private var canRescheduleOrCancelSession: Bool {
        exchange.status == .accepted && sessionPhase == .confirmed && sessionIsFuture
    }
    private var canCancelExchange: Bool {
        exchange.status == .accepted || (exchange.status == .pending && !exchange.isIncoming)
    }
    private var hasHeaderMenu: Bool { canRescheduleOrCancelSession || canCancelExchange }

    private var headerMenu: some View {
        Menu {
            if canRescheduleOrCancelSession {
                Button { showSchedule = true } label: {
                    Label("Propose Reschedule", systemImage: "calendar.badge.clock")
                }
                Button(role: .destructive) { showCancelSession = true } label: {
                    Label("Cancel Session", systemImage: "calendar.badge.exclamationmark")
                }
            }
            if canCancelExchange {
                Button(role: .destructive) { showCancelExchange = true } label: {
                    Label("Cancel Exchange", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.charcoal)
                .frame(width: 44, height: 44)
                .background(Theme.surface.opacity(0.9), in: Circle())
        }
        .accessibilityLabel("More options")
    }

    private var otherStudentProfile: StudentProfileView {
        StudentProfileView(
            name: exchange.studentName,
            major: exchange.studentMajor,
            teaches: exchange.learningSkill,        // they teach what YOU learn
            wantsToLearn: exchange.offeringSkill,   // they want what YOU teach
            availability: "Shared once you connect",
            initials: exchange.initials,
            bannerColors: exchange.bannerColors,
            imageURL: exchange.imageURL,
            localImageName: exchange.localImageName,
            communityAuthorID: UUID(uuidString: exchange.otherID)
        )
    }

    @ViewBuilder private var headerVisual: some View {
        let scrim = LinearGradient(colors: exchange.bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        if let local = exchange.localImageName {
            Image(local).resizable().scaledToFill().scaleEffect(1.1).blur(radius: 26).opacity(0.95)
        } else if let url = exchange.imageURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill().scaleEffect(1.1).blur(radius: 26).opacity(0.95) }
                else { scrim }
            }
        } else {
            scrim
        }
    }

    @ViewBuilder private var avatar: some View {
        let size: CGFloat = 64
        Group {
            if let local = exchange.localImageName {
                Image(local).resizable().scaledToFill()
            } else if let url = exchange.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { avatarFallback(size) }
                }
            } else {
                avatarFallback(size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    private func avatarFallback(_ size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: exchange.bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(exchange.initials).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(.white)
        }
    }

    // MARK: - Skill Swap (one cohesive container)

    private var skillSwapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Skill Swap")
            HStack(alignment: .center, spacing: 12) {
                skillBlock("YOU LEARN", exchange.learningSkill, symbol: "book.closed.fill",
                           tint: Theme.brightLavender)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                skillBlock("YOU TEACH", exchange.offeringSkill, symbol: "lightbulb.fill",
                           tint: Theme.powderBlue)
            }
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            .softCardShadow()
        }
    }

    private func skillBlock(_ label: String, _ value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16)).foregroundStyle(Theme.charcoal)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Theme.mutedStone)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session (conditional)

    @ViewBuilder private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(sessionPhase == .cancelled ? "Session History" : "Your Session")

            switch sessionPhase {
            case .none:
                EmptyView()
            case .proposed, .confirmed:
                VStack(alignment: .leading, spacing: 10) {
                    sessionDetailCard
                    if rescheduleProposed {
                        SubtleNote(text: "Reschedule proposed · pending \(firstName)'s approval. The current session stands until they approve.")
                    }
                }
            case .cancelled:
                infoCard(symbol: "calendar.badge.exclamationmark", title: "Session cancelled",
                         detail: "This session was cancelled. Your exchange is still active — schedule a new time below.")
            }
        }
    }

    // Formatted pieces from the real/seeded session.
    private var sessionDateText: String {
        guard let d = session?.scheduledAt else { return "Date to be confirmed" }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    private var sessionTimeText: String? {
        guard let start = session?.scheduledAt else { return nil }
        let end = Calendar.current.date(byAdding: .minute, value: session?.durationMinutes ?? 60, to: start) ?? start
        let t = Date.FormatStyle.dateTime.hour().minute()
        return "\(start.formatted(t)) – \(end.formatted(t))"
    }
    private var sessionFormatText: String {
        guard let s = session else { return "" }
        if let detail = s.locationOrLink, !detail.isEmpty { return "\(s.format) · \(detail)" }
        return s.format
    }
    private var sessionStatusText: String {
        switch sessionPhase {
        case .confirmed: return sessionIsFuture ? "Confirmed · upcoming" : "Confirmed"
        case .proposed:  return proposedByMe ? "Awaiting \(firstName)'s confirmation" : "Proposed by \(firstName)"
        default:         return "—"
        }
    }

    private var sessionDetailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sessionDateText).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            if let time = sessionTimeText {
                Text(time).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal.opacity(0.85))
            }
            HairlineDivider()
            sessionRow(session?.format == "In Person" ? "mappin.and.ellipse" : "video", sessionFormatText)
            sessionRow(sessionPhase == .confirmed ? "checkmark.circle.fill" : "clock", sessionStatusText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    private func sessionRow(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.primaryAction).frame(width: 22)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.charcoal)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Completion (two-party)

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Confirm Completion")
            VStack(spacing: 12) {
                completionRow(name: "You", done: youCompleted)
                Divider()
                completionRow(name: firstName, done: otherCompleted)
            }
            .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))

            SubtleNote(text: "An exchange is completed only when BOTH participants confirm after the session. Neither can confirm for the other.")
        }
    }

    private func completionRow(name: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(done ? .green : Theme.mutedStone)
            Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
            Spacer()
            Text(done ? "Confirmed" : "Pending").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(done ? .green : Theme.mutedStone)
        }
    }

    // MARK: - Completed summary + Kudos

    private var completedSummary: some View {
        infoCard(symbol: "checkmark.seal.fill", title: "Exchange completed",
                 detail: "You and \(firstName) both confirmed this skill exchange.")
    }

    private var kudosSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("SkillSwap Kudos")
            if kudosGiven {
                infoCard(symbol: "heart.fill", title: "Kudos sent",
                         detail: "You've already sent kudos to \(firstName) for this exchange.")
            } else {
                Button { showKudos = true } label: { primaryLabel("Send Kudos to \(firstName)") }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Primary action bar (contextual)

    @ViewBuilder private var primaryActionBar: some View {
        switch primaryAction {
        case .acceptDecline:
            HStack(spacing: 12) {
                Button { showDeclineConfirmation = true } label: { secondaryLabel("Decline") }
                    .buttonStyle(.plain).disabled(isWorking)
                Button {
                    perform({ try await exchangeService.accept(exchangeID: exchange.id) }, setStatus: .accepted, dismissAfter: false)
                } label: { primaryLabel(isWorking ? "Working…" : "Accept Exchange") }
                    .buttonStyle(.plain).disabled(isWorking)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)

        case .schedule:
            Button { showSchedule = true } label: { primaryLabel("Schedule Session") }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)

        case .reviewSession:
            // The other student proposed — Accept or Decline. Only the OTHER
            // participant can confirm (enforced by the DB); your own proposal
            // shows "Awaiting Confirmation" instead.
            HStack(spacing: 12) {
                Button {
                    if let sid = session?.id { sessionAction { try await exchangeService.cancelSession(sessionID: sid) } }
                } label: { secondaryLabel("Decline") }
                    .buttonStyle(.plain).disabled(isWorking)
                Button {
                    if let sid = session?.id { sessionAction { try await exchangeService.confirmSession(sessionID: sid) } }
                } label: { primaryLabel(isWorking ? "Working…" : "Accept Session") }
                    .buttonStyle(.plain).disabled(isWorking)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)

        case .confirmCompletion:
            Button {
                confirmCompletionAction()
            } label: {
                primaryLabel(youCompleted ? "Waiting for \(firstName)" : (isWorking ? "Working…" : "Confirm Completion"))
            }
            .buttonStyle(.plain)
            .disabled(youCompleted || isWorking)
            .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)

        case .awaitingResponse:
            infoBar("Awaiting Response", symbol: "hourglass")
        case .awaitingConfirmation:
            infoBar("Awaiting \(firstName)'s Confirmation", symbol: "hourglass")
        case .none:
            EmptyView()
        }
    }

    private func infoBar(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol); Text(text).font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(Theme.mutedStone)
        .frame(maxWidth: .infinity).padding(16)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)
    }

    // MARK: - Reusable bits

    private func infoCard(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Theme.primaryAction)
                .frame(width: 44, height: 44)
                .background(Theme.brightLavender.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.charcoal)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    private func primaryLabel(_ title: String) -> some View {
        HStack { Text(title).font(.system(size: 15, weight: .semibold)); Spacer(); Image(systemName: "arrow.up.right") }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(18)
            .background(Theme.primaryAction).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func secondaryLabel(_ title: String, fill: Bool = false) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.charcoal).frame(maxWidth: .infinity).padding(18)
            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.charcoal).tracking(-0.3)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var exchange = SkillExchange(
        id: "preview", studentName: "Sara Ahmed", studentMajor: "Computer Science",
        initials: "SA", learningSkill: "Swift Programming", offeringSkill: "UI/UX Design",
        status: .accepted, isIncoming: false, date: "Oct 17",
        bannerColors: [Color(red: 0.73, green: 0.68, blue: 1.0), Color(red: 0.94, green: 0.76, blue: 0.94)]
    )
    NavigationStack { ExchangeDetailsView(exchange: $exchange) }
}
