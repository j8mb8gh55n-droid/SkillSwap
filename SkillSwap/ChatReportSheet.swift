import SwiftUI

struct ChatReportSheet: View {
    enum Reason: String, CaseIterable, Identifiable {
        case harassment, spam, inappropriateContent = "inappropriate_content", safetyConcern = "safety_concern", other

        var id: Self { self }
        var title: String {
            switch self {
            case .harassment: "Harassment"
            case .spam: "Spam"
            case .inappropriateContent: "Inappropriate content"
            case .safetyConcern: "Safety concern"
            case .other: "Other"
            }
        }
    }

    let conversationID: UUID
    let evidence: [ChatMessage]
    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason?
    @State private var details = ""
    @State private var messageID: Int64?
    @State private var submitting = false
    @State private var submitted = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        Label("Report submitted", systemImage: "checkmark.circle")
                        Text("Your report was submitted privately.")
                        Button("Done") { dismiss() }
                    }
                } else {
                    Section {
                        Picker("Reason", selection: $reason) {
                            Text("Select a reason").tag(nil as Reason?)
                            ForEach(Reason.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                        TextField("Additional details (optional)", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                        if details.unicodeScalars.count > 500 {
                            Text("Use 500 characters or fewer.").foregroundStyle(.red)
                        }
                    }
                    if !evidence.isEmpty {
                        Section("Message evidence (optional)") {
                            Picker("Message", selection: $messageID) {
                                Text("None").tag(nil as Int64?)
                                ForEach(evidence) { message in
                                    Text(String(message.text.prefix(100))).tag(Optional(message.id))
                                }
                            }
                        }
                    }
                    Section {
                        if let error {
                            Text(error).foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await submit() }
                        } label: {
                            if submitting { ProgressView("Submitting report") }
                            else { Text("Submit Report") }
                        }
                        .disabled(reason == nil || submitting || details.unicodeScalars.count > 500)
                    }
                    .disabled(submitting)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmIvory.ignoresSafeArea())
            .navigationTitle("Report Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !submitted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(submitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(submitting)
    }

    private func submit() async {
        guard !submitting, !submitted, let reason, details.unicodeScalars.count <= 500 else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            try await MessagingService().report(conversation: conversationID, reason: reason.rawValue,
                                                message: messageID, details: details)
            submitted = true
        } catch {
            if !MessagingError.cancelled(error) { self.error = MessagingService.reportErrorText(for: error) }
        }
    }
}
