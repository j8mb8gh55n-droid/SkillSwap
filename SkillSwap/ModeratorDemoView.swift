#if DEBUG
import SwiftUI

struct ModeratorDemoView: View {
    private enum Status: String, CaseIterable {
        case pending = "Pending"
        case reviewed = "Reviewed"
        case resolved = "Resolved"
    }

    private struct DemoReport: Identifiable {
        let id: Int
        let student: String
        let reason: String
        let details: String
        let evidence: String?
        var status: Status = .pending
    }

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Status = .pending
    @State private var reports = [
        DemoReport(id: 1, student: "Sample Student A", reason: "Spam",
                   details: "Repeated promotional messages in a study conversation.",
                   evidence: "Sample message: Sign up for this promotion."),
        DemoReport(id: 2, student: "Sample Student B", reason: "Harassment",
                   details: "The student reported repeated unwanted contact.", evidence: nil)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Moderator Demo", dismiss: dismiss)
                Text("Synthetic reports. Review actions reset when you leave.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Report status", selection: $filter) {
                    ForEach(Status.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                let filtered = reports.filter { $0.status == filter }
                if filtered.isEmpty {
                    Text("No sample reports in this group.").foregroundStyle(.secondary)
                } else {
                    SettingsGroup(filter.rawValue) {
                        ForEach(filtered) { report in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(report.details)
                                    if let evidence = report.evidence {
                                        Text("Sample evidence").font(.headline)
                                        Text(evidence)
                                    }
                                    if report.status == .pending {
                                        Button("Mark Reviewed") { move(report.id, to: .reviewed) }
                                    }
                                    if report.status != .resolved {
                                        Button("Resolve") { move(report.id, to: .resolved) }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                                .buttonStyle(.bordered)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(report.reason).font(.headline)
                                    Text(report.student).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            if report.id != filtered.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.vertical, 10)
        }
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func move(_ id: Int, to status: Status) {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[index].status = status
    }
}
#endif
