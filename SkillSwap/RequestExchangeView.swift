//
//  RequestExchangeView.swift
//  SkillSwap
//

import SwiftUI

struct RequestExchangeView: View {

    // MARK: - Student Information

    let studentName: String
    let studentMajor: String
    let studentTeaches: String
    let studentWantsToLearn: String
    let studentInitials: String
    let bannerColors: [Color]

    /// Real recipient (profile id + skill ids) when opened from discovery.
    /// Carried for Phase C exchange creation; the send flow is still stubbed.
    var recipient: DiscoveredStudent? = nil

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var message = ""
    @State private var learningGoal = ""
    @State private var preferredFormat = "no_preference"
    @State private var showConfirmation = false

    private let formatOptions: [(value: String, label: String)] = [
        ("online", "Online"), ("in_person", "In Person"), ("no_preference", "Either")
    ]

    // Real skills + submission state (Phase C1).
    @State private var myTeaching: [CatalogSkill] = []
    @State private var offered: CatalogSkill?
    @State private var requested: CatalogSkill?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let service = ExchangeService()

    private var recipientSkills: [CatalogSkill] { recipient?.teaches ?? [] }

    // MARK: - Colors (adaptive — map to Theme so dark mode coheres)

    private let cream = Theme.warmIvory      // adaptive screen background
    private let ink = Theme.ink              // adaptive high-contrast text
    private let lavender = Theme.brightLavender  // pastel accent (both modes)

    // MARK: - Validation

    private var canSubmit: Bool {
        recipient != nil && offered != nil && requested != nil && !isSubmitting && !recipientUnavailable
    }

    /// Phase D5: the recipient isn't accepting new requests (defense-in-depth;
    /// the backend trigger also rejects, handled gracefully in submit()).
    private var recipientUnavailable: Bool {
        AvailabilityStatus.from(recipient?.availabilityStatus) == .unavailable
    }

    private var firstName: String {
        studentName.components(separatedBy: " ").first
        ?? studentName
    }

    // MARK: - Body

    var body: some View {

        ZStack {

            cream
                .ignoresSafeArea()

            ScrollView {

                VStack(alignment: .leading, spacing: 28) {

                    header

                    partnerCard

                    if recipientUnavailable {
                        SubtleNote(
                            text: "\(firstName) isn't accepting new exchange requests right now.",
                            systemImage: "pause.circle"
                        )
                    }

                    exchangeSection

                    preferencesSection

                    messageSection

                    infoNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            bottomButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let loaded = try? await service.fetchMyTeachingSkills() {
                myTeaching = loaded
                if offered == nil { offered = loaded.first }
            }
            if requested == nil { requested = recipient?.teaches.first }
        }
        .alert("Request Sent!", isPresented: $showConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your request was sent to \(firstName). You'll find it in My Exchanges.")
        }
        .alert("Couldn't Send Request", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Submit (real Supabase insert)

    private func submit() {
        guard let recipient, let offered, let requested, !isSubmitting else { return }
        isSubmitting = true
        Task {
            do {
                try await service.createExchange(
                    recipientID: recipient.id,
                    offeredSkillID: offered.id,
                    requestedSkillID: requested.id,
                    message: message,
                    learningGoal: learningGoal,
                    preferredFormat: preferredFormat
                )
                isSubmitting = false
                showConfirmation = true
            } catch {
                isSubmitting = false
                errorMessage = (error as? ExchangeService.ExchangeCreateError)?.errorDescription
                    ?? "We couldn't send your request. Please try again."
            }
        }
    }

    // MARK: - Header

    private var header: some View {

        VStack(alignment: .leading, spacing: 14) {

            Button {
                dismiss()
            } label: {

                BackChevron()
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 7) {

                HStack(spacing: 7) {

                    Text("SKILL EXCHANGE")
                        .font(
                            .system(
                                size: 11,
                                weight: .heavy
                            )
                        )
                        .tracking(2)

                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                }

                Text("Make a swap.")
                    .font(
                        .system(
                            size: 39,
                            weight: .black
                        )
                    )
                    .tracking(-1.2)

                Text(
                    "Share what you know. Learn something new."
                )
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Exchange Partner

    private var partnerCard: some View {

        HStack(spacing: 14) {

            ZStack {

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: bannerColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 65, height: 65)

                Text(studentInitials)
                    .font(
                        .system(
                            size: 20,
                            weight: .black
                        )
                    )
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {

                Text("EXCHANGING WITH")
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(.secondary)

                Text(studentName)
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )

                Text(studentMajor)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.09))
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: 22)
        )
    }

    // MARK: - Exchange Section

    private var exchangeSection: some View {

        VStack(alignment: .leading, spacing: 16) {

            sectionTitle("Your Exchange")

            // What the student wants to learn

            VStack(alignment: .leading, spacing: 9) {

                Text("I WANT TO LEARN")
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(.secondary)

                if recipientSkills.count > 1 {
                    Menu {
                        ForEach(recipientSkills) { skill in
                            Button { requested = skill } label: {
                                if requested?.id == skill.id { Label(skill.name, systemImage: "checkmark") }
                                else { Text(skill.name) }
                            }
                        }
                    } label: { wantToLearnCard(showChevron: true) }
                } else {
                    wantToLearnCard(showChevron: false)
                }
            }

            // What the current user can teach

            VStack(alignment: .leading, spacing: 9) {

                Text("I CAN OFFER")
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(.secondary)

                Menu {

                    ForEach(myTeaching) { skill in
                        Button { offered = skill } label: {
                            if offered?.id == skill.id { Label(skill.name, systemImage: "checkmark") }
                            else { Text(skill.name) }
                        }
                    }

                } label: {

                    HStack(spacing: 12) {

                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.black)
                            .frame(width: 46, height: 46)
                            .background(
                                Color(
                                    red: 1.0,
                                    green: 0.85,
                                    blue: 0.89
                                )
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 4) {

                            Text(offered?.name ?? (myTeaching.isEmpty ? "Add a teaching skill first" : "Choose a skill"))
                            .font(
                                .system(
                                    size: 15,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(offered == nil ? Color.secondary : .primary)

                            Text(offered != nil ? "You'll share this skill" : "Select something you can teach")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .background(Theme.surface)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 19)
                    )
                }
            }

            // Suggested match

            if myTeaching.contains(where: { $0.name.caseInsensitiveCompare(studentWantsToLearn) == .orderedSame }) {

                HStack(spacing: 8) {

                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)

                    Text(
                        "\(firstName) wants to learn \(studentWantsToLearn)!"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 3)
            }
        }
    }

    // The recipient's skill the user wants to learn (requested_skill). Same card
    // styling as before; a chevron appears only when there's more than one.
    private func wantToLearnCard(showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18)).foregroundStyle(.black)
                .frame(width: 46, height: 46).background(lavender)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(requested?.name ?? recipientSkills.first?.name ?? studentTeaches)
                    .font(.system(size: 15, weight: .semibold))
                Text(requested != nil ? "You'll learn this from \(firstName)" : "Choose a skill to learn")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: showChevron ? "chevron.up.chevron.down" : "checkmark.circle.fill")
                .font(.system(size: showChevron ? 12 : 16))
                .foregroundStyle(showChevron ? Color.secondary : .purple)
        }
        .padding(15).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 19))
    }

    // MARK: - Preferences (optional learning goal + preferred format)

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 9) {
                Text("PREFERRED FORMAT")
                    .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(formatOptions, id: \.value) { opt in
                        let on = preferredFormat == opt.value
                        Button { preferredFormat = opt.value } label: {
                            Text(opt.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? .white : .black)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(on ? Theme.primaryAction : Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("LEARNING GOAL")
                        .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Text("OPTIONAL")
                        .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Image(systemName: "target").foregroundStyle(.purple)
                    TextField("What do you want to achieve?", text: $learningGoal)
                        .font(.system(size: 14))
                }
                .padding(15).background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 19))
            }
        }
    }

    // MARK: - Personal Message

    private var messageSection: some View {

        VStack(alignment: .leading, spacing: 13) {

            HStack {

                sectionTitle("Add a Message")

                Spacer()

                Text("OPTIONAL")
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {

                if message.isEmpty {

                    Text(
                        "Hi \(firstName)! I'd love to learn \(studentTeaches) from you..."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.gray.opacity(0.7))
                    .padding(.horizontal, 17)
                    .padding(.top, 19)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $message)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(height: 125)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(Theme.surface)
            .clipShape(
                RoundedRectangle(cornerRadius: 20)
            )

            Text("\(message.count)/300 characters")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )
        }
        .onChange(of: message) { _, newValue in

            if newValue.count > 300 {
                message = String(newValue.prefix(300))
            }
        }
    }

    // MARK: - Information Note

    private var infoNote: some View {

        HStack(alignment: .top, spacing: 11) {

            Image(systemName: "info.circle.fill")
                .foregroundStyle(.purple)

            Text(
                "Once your request is accepted, you and \(firstName) can arrange a time for your skill exchange."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(lavender.opacity(0.25))
        .clipShape(
            RoundedRectangle(cornerRadius: 17)
        )
    }

    // MARK: - Section Title

    private func sectionTitle(_ title: String) -> some View {

        Text(title)
            .font(
                .system(
                    size: 21,
                    weight: .bold
                )
            )
            .tracking(-0.4)
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {

        Button {
            submit()
        } label: {

            HStack {

                Text(isSubmitting ? "Sending…" : "Send Exchange Request")
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )

                Spacer()

                if isSubmitting { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.up.right") }
            }
            .foregroundStyle(.white)
            .padding(19)
            .background(
                canSubmit
                ? Theme.primaryAction
                : Color.gray.opacity(0.45)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(cream)
    }
}

// MARK: - Preview

#Preview {

    NavigationStack {

        RequestExchangeView(
            studentName: "Sara Ahmed",
            studentMajor: "Computer Science",
            studentTeaches: "Swift Programming",
            studentWantsToLearn: "UI/UX Design",
            studentInitials: "SA",
            bannerColors: [
                Color(red: 0.73, green: 0.68, blue: 1.0),
                Color(red: 0.94, green: 0.76, blue: 0.94)
            ]
        )
    }
}
