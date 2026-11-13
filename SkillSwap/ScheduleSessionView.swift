//
//  ScheduleSessionView.swift
//  SkillSwap
//
//  Compact session proposal form. Proposing creates a PROPOSAL (status
//  "proposed") — the other student must confirm; it is never auto-confirmed.
//  Returns a SessionInfo to the caller via onPropose.
//
//  NOTE: not yet persisted to Supabase (the session write-flow is pending);
//  the proposal updates the Exchange Details view locally for now.
//

import SwiftUI

private enum SessionFormat: String, CaseIterable, Identifiable {
    case online = "Online"
    case inPerson = "In Person"
    var id: String { rawValue }
    var symbol: String { self == .online ? "video.fill" : "person.2.fill" }
}

struct ScheduleSessionView: View {

    let studentName: String
    let studentMajor: String
    let studentInitials: String
    let learningSkill: String
    let bannerColors: [Color]

    /// The exchange this session belongs to (real insert). When nil (previews),
    /// the form just confirms without persisting.
    var exchangeID: String? = nil
    /// Called after a successful proposal so the caller can refresh.
    var onProposed: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date().addingTimeInterval(3600)
    @State private var selectedDuration = 60
    @State private var selectedFormat: SessionFormat = .online
    @State private var meetingDetails = ""
    @State private var attemptedSubmit = false
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var submitError: String?
    private let service = ExchangeService()

    private let durations = [30, 45, 60, 90]

    private var firstName: String { studentName.components(separatedBy: " ").first ?? studentName }
    private var trimmedDetails: String { meetingDetails.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dateIsFuture: Bool { selectedDate > Date() }
    private var detailsFilled: Bool { !trimmedDetails.isEmpty }
    private var canSchedule: Bool { dateIsFuture && detailsFilled }

    var body: some View {
        ZStack {
            Theme.warmIvory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    studentRow
                    dateTimeSection
                    durationSection
                    formatSection
                    meetingDetailsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { proposeBar }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Session Proposed", isPresented: $showConfirmation) {
            Button("OK") { onProposed?(); dismiss() }
        } message: {
            Text("Your proposal was sent to \(firstName) to confirm. They'll need to approve the time.")
        }
        .alert("Couldn't Propose Session", isPresented: Binding(
            get: { submitError != nil }, set: { if !$0 { submitError = nil } })) {
            Button("OK", role: .cancel) { submitError = nil }
        } message: {
            Text(submitError ?? "Please try again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 4) {
                Text("Make time to learn.")
                    .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
                Text("Propose a time for your \(learningSkill) session.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
            }
        }
        .padding(.top, 4)
    }

    private var studentRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(studentInitials).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(studentName).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.charcoal)
                Text(studentMajor).font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Date & time (compact)

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Date & Time")
            VStack(spacing: 0) {
                DatePicker("Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                HairlineDivider().padding(.vertical, 6)
                DatePicker("Time", selection: $selectedDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
            }
            .tint(Theme.primaryAction)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            if attemptedSubmit && !dateIsFuture {
                validationText("This time has passed. Choose a later time or another day.")
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Duration")
            HStack(spacing: 9) {
                ForEach(durations, id: \.self) { d in
                    let on = selectedDuration == d
                    Button { selectedDuration = d } label: {
                        Text("\(d) min")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.charcoal)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(on ? Theme.primaryAction : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Format")
            HStack(spacing: 12) {
                ForEach(SessionFormat.allCases) { f in
                    let on = selectedFormat == f
                    Button { selectedFormat = f; meetingDetails = "" } label: {
                        HStack(spacing: 8) {
                            Image(systemName: f.symbol); Text(f.rawValue)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? .white : Theme.charcoal)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(on ? Theme.primaryAction : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Meeting details

    private var meetingDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label(selectedFormat == .online ? "Meeting Link" : "Location")
            HStack(spacing: 12) {
                Image(systemName: selectedFormat == .online ? "link" : "mappin.and.ellipse")
                    .foregroundStyle(Theme.primaryAction)
                TextField(selectedFormat == .online ? "Paste a meeting link" : "Enter a meeting place",
                          text: $meetingDetails)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(selectedFormat == .online ? .never : .sentences)
                    .autocorrectionDisabled(selectedFormat == .online)
                    .keyboardType(selectedFormat == .online ? .URL : .default)
            }
            .padding(16)
            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
            if attemptedSubmit && !detailsFilled {
                validationText(selectedFormat == .online ? "Paste the link your partner will use to join." : "Enter where you and your partner will meet.")
            }
        }
    }

    // MARK: - Propose

    private var proposeBar: some View {
        Button { propose() } label: {
            HStack {
                Text(isSubmitting ? "Proposing…" : "Propose Session").font(.system(size: 15, weight: .semibold))
                Spacer()
                if isSubmitting { ProgressView().tint(.white) } else { Image(systemName: "arrow.up.right") }
            }
            .foregroundStyle(.white).padding(18)
            .background(canSchedule && !isSubmitting ? Theme.primaryAction : Color.gray.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)
    }

    private func propose() {
        attemptedSubmit = true
        guard canSchedule, !isSubmitting else { return }
        guard let exchangeID else { showConfirmation = true; return }  // preview path
        isSubmitting = true
        Task {
            do {
                try await service.proposeSession(
                    exchangeID: exchangeID,
                    scheduledAt: selectedDate,
                    durationMinutes: selectedDuration,
                    format: selectedFormat == .online ? "online" : "in_person",
                    locationOrLink: trimmedDetails
                )
                isSubmitting = false
                showConfirmation = true
            } catch {
                isSubmitting = false
                submitError = dateIsFuture
                    ? "We couldn't send your proposal. Try again."
                    : "This time has passed. Choose a later time and try again."
            }
        }
    }

    // MARK: - Bits

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.mutedStone)
    }

    private func validationText(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScheduleSessionView(
            studentName: "Sara Ahmed", studentMajor: "Computer Science",
            studentInitials: "SA", learningSkill: "Swift Programming",
            bannerColors: [Color(red: 0.73, green: 0.68, blue: 1.0), Color(red: 0.94, green: 0.76, blue: 0.94)]
        )
    }
}
