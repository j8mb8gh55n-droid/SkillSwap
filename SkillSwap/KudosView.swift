//
//  KudosView.swift
//  SkillSwap
//
//  Phase D1: compose and submit a real SkillSwap Kudos (positive appreciation)
//  after a VERIFIED completed exchange. Multi-select appreciation tags + an
//  optional ≤300-char message, saved to public.kudos via RLS as the signed-in
//  user. Same approved design — the chips are now multi-select.
//

import SwiftUI

struct KudosView: View {

    let partnerName: String
    let exchangeID: String
    let recipientID: String
    /// Called after a successful submission so the caller can refresh.
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTags: Set<String> = []
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let service = ExchangeService()

    // Exact approved tag strings (must match the DB CHECK).
    private let tags = [
        "Patient teacher", "Super clear", "Really kind",
        "Great energy", "Went the extra mile"
    ]

    private var canSend: Bool { !selectedTags.isEmpty && !isSubmitting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30)).foregroundStyle(.pink)
                    Text("Send Kudos")
                        .font(.system(size: 30, weight: .black)).tracking(-1)
                        .foregroundStyle(Theme.ink)
                    Text("Share a little appreciation for \(partnerName).")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("PICK A FEW").font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 9, alignment: .leading)],
                        alignment: .leading, spacing: 9
                    ) {
                        ForEach(tags, id: \.self) { tag in
                            let on = selectedTags.contains(tag)
                            Button {
                                if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? .white : Theme.charcoal)
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    .frame(maxWidth: .infinity)
                                    .background(on ? Theme.primaryAction : Theme.surface)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: on ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("ADD A NOTE (OPTIONAL)").font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Say thanks in your own words…")
                                .font(.system(size: 14)).foregroundStyle(.gray.opacity(0.7))
                                .padding(.horizontal, 17).padding(.top, 19)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    .onChange(of: message) { _, v in if v.count > 300 { message = String(v.prefix(300)) } }

                    Text("\(message.count)/300")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Button { submit() } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(isSubmitting ? "Sending…" : "Send Kudos").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        if isSubmitting { ProgressView().tint(.white) }
                    }
                    .foregroundStyle(.white).padding(18)
                    .frame(maxWidth: .infinity)
                    .background(canSend ? Theme.primaryAction : Color.gray.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(Theme.Spacing.screenH)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cream.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.ink)
            }
        }
        .alert("Couldn't Send Kudos", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func submit() {
        guard canSend else { return }
        isSubmitting = true
        Task {
            do {
                try await service.giveKudos(
                    exchangeID: exchangeID, recipientID: recipientID,
                    tags: Array(selectedTags),
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                isSubmitting = false
                onSent()
                dismiss()
            } catch {
                isSubmitting = false
                let desc = String(describing: error).lowercased()
                errorMessage = (desc.contains("duplicate") || desc.contains("unique"))
                    ? "You've already sent kudos for this exchange."
                    : "We couldn't send your kudos. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        KudosView(partnerName: "Sara", exchangeID: "x", recipientID: "r")
    }
}
