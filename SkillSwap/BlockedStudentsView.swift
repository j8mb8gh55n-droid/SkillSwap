import SwiftUI

struct BlockedStudentsView: View {
    static let unblockExplanation = "Unblocking removes your block. Messaging does not reopen automatically."
    static let blocksChanged = Notification.Name("SkillSwap.ownedChatBlocksChanged")

    private let isPreview: Bool

    init(previewStudents: [ChatParticipant]? = nil, previewLoading: Bool = false, previewError: String? = nil) {
        isPreview = previewStudents != nil || previewLoading || previewError != nil
        _students = State(initialValue: previewStudents)
        _error = State(initialValue: previewError)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var students: [ChatParticipant]?
    @State private var loading = false
    @State private var updating: UUID?
    @State private var target: ChatParticipant?
    @State private var error: String?
    private let service = MessagingService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Blocked Students", dismiss: dismiss)
                if let error {
                    EmptyStateView(systemImage: "exclamationmark.circle", title: "Couldn’t update blocked students",
                                   message: error, actionTitle: "Retry", action: { Task { await load() } })
                }
                if let students {
                    if students.isEmpty && error == nil {
                        EmptyStateView(systemImage: "hand.raised", title: "No blocked students",
                                       message: "Students you block in chat will appear here.")
                    } else if !students.isEmpty {
                        SettingsGroup("Messaging") {
                            ForEach(students, id: \.id) { student in
                                row(student)
                                if student.id != students.last?.id {
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                    }
                } else if error == nil {
                    ProgressView("Loading blocked students")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.top, 10)
        }
        .skillSwapScreen(background: Theme.warmIvory)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Self.blocksChanged)) { _ in
            Task { await load() }
        }
        .alert("Unblock student?", isPresented: Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        ), presenting: target) { student in
            Button("Cancel", role: .cancel) {}
            Button("Unblock") { Task { await unblock(student) } }
        } message: { _ in
            Text(Self.unblockExplanation)
        }
    }

    private func row(_ student: ChatParticipant) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity(student)
                Spacer(minLength: 8)
                unblockButton(student)
            }
            VStack(alignment: .leading, spacing: 8) {
                identity(student)
                unblockButton(student)
            }
        }
        .padding(12)
    }

    private func identity(_ student: ChatParticipant) -> some View {
        HStack(spacing: 12) {
            ChatAvatar(participant: student)
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name).font(.headline).foregroundStyle(Theme.ink)
                Text("Blocked").font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func unblockButton(_ student: ChatParticipant) -> some View {
        Button { target = student } label: {
            Group {
                if updating == student.id { ProgressView().accessibilityLabel("Unblocking") }
                else { Text("Unblock") }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(updating == student.id ? "Unblocking \(student.name)" : "Unblock \(student.name)")
        .disabled(updating != nil || loading)
    }

    private func load() async {
        guard !isPreview, !loading, updating == nil else { return }
        loading = true
        defer { loading = false }
        do {
            let updated = try await service.blockedStudents()
            try Task.checkCancellation()
            students = updated
            error = nil
        } catch {
            if !MessagingError.cancelled(error) { self.error = MessagingError.text(for: error) }
        }
    }

    private func unblock(_ student: ChatParticipant) async {
        guard !isPreview, updating == nil, !loading, students?.contains(where: { $0.id == student.id }) == true else { return }
        updating = student.id
        error = nil
        do {
            try await service.unblock(student: student.id)
            students?.removeAll { $0.id == student.id }
            NotificationCenter.default.post(name: Self.blocksChanged, object: nil)
        } catch {
            if !MessagingError.cancelled(error) { self.error = MessagingError.text(for: error) }
        }
        updating = nil
        if error == nil { await load() }
    }
}
