import SwiftUI

struct ChatExchangeView: View {
    let participant: ChatParticipant
    @State private var exchange: SkillExchange?
    @State private var student: DiscoveredStudent?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let binding = Binding($exchange) {
                ExchangeDetailsView(exchange: binding)
            } else if let student, AvailabilityStatus.from(student.availabilityStatus).acceptsRequests {
                let card = student.card(colorIndex: 0)
                RequestExchangeView(studentName: student.name, studentMajor: student.major,
                                    studentTeaches: card.teaches.joined(separator: ", "), studentWantsToLearn: card.learns.joined(separator: ", "),
                                    studentInitials: student.initials, bannerColors: card.bannerColors,
                                    recipient: student)
            } else if loading {
                ProgressView("Loading exchange")
            } else {
                ContentUnavailableView {
                    Label("Exchange unavailable", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text(errorMessage ?? "This student is not currently accepting exchange requests.")
                } actions: {
                    if errorMessage != nil {
                        Button("Retry") { Task { await load() } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.warmIvory.ignoresSafeArea())
        .navigationTitle("Exchange")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(exchange == nil && student.map { AvailabilityStatus.from($0.availabilityStatus).acceptsRequests } != true ? .visible : .automatic, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let matches = try await ExchangeService().fetchMyExchanges().filter {
                UUID(uuidString: $0.otherID) == participant.id
            }
            if let match = matches.first(where: { $0.status == .accepted || $0.status == .pending }) ?? matches.first {
                exchange = match.asExchange
            } else {
                student = try await StudentDiscoveryService().fetchProfile(id: participant.id)
            }
        } catch {
            if !MessagingError.cancelled(error) { errorMessage = "The exchange could not be loaded. Try again." }
        }
    }
}
