import SwiftUI

/// What landed, after a successful import. Presented as a sheet so the system owns its own
/// chrome; the figures themselves sit on plain opaque rows, because dense numbers are the
/// one thing that must never be read through a moving material.
struct ImportSummaryView: View {
    let summary: ImportSummary
    let onDismiss: () -> Void
    let onImportAnother: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accountRow
                    if let period = summary.period {
                        LabeledContent("Period", value: Self.periodText(period))
                            .monospacedDigit()
                    }
                }

                Section("Imported") {
                    figure("Transactions", summary.transactionsImported)
                    figure("Categorized", summary.categorized)
                    figure("Left uncategorized", summary.uncategorized)
                    if summary.duplicatesSkipped > 0 {
                        figure("Duplicates skipped", summary.duplicatesSkipped)
                    }
                    if summary.unreadableRows > 0 {
                        figure("Rows Kaname couldn't read", summary.unreadableRows)
                    }
                }

                if let notice = summary.integrity.notice {
                    Section {
                        Label {
                            Text(notice.message)
                        } icon: {
                            Image(systemName: notice.symbolName)
                                .foregroundStyle(notice.isWarning ? .orange : .green)
                        }
                    }
                }

                // Said plainly, and above nothing else: an empty import that Kaname cannot
                // vouch for must never be left to read as "you had no spending".
                if summary.nothingRecognized {
                    Section {
                        Label {
                            Text(ImportSummary.nothingRecognizedNotice.message)
                        } icon: {
                            Image(systemName: ImportSummary.nothingRecognizedNotice.symbolName)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Import complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Import another", action: onImportAnother)
                }
            }
        }
    }

    /// The issuer names itself and the last-4 is shown whenever the statement carried one, so
    /// the person can always tell which account this landed in — and see which reader claimed
    /// a document two of them recognised.
    private var accountRow: some View {
        LabeledContent {
            Text(summary.last4.map { "•••• \($0)" } ?? "")
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.issuerDisplayName)
                if summary.accountIsNew {
                    Text("New account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ count: Int) -> some View {
        LabeledContent(label, value: count.formatted())
            .monospacedDigit()
            .accessibilityLabel("\(label): \(count)")
    }

    private static func periodText(_ period: DateInterval) -> String {
        let start = period.start.formatted(.dateTime.day().month(.abbreviated).year())
        let end = period.end.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) – \(end)"
    }
}

#Preview {
    ImportSummaryView(
        summary: ImportSummary(
            // Deliberately not a real bank: the app never knows which issuers exist, it only
            // renders whatever name the engine handed back.
            issuerDisplayName: "Example Bank Credit Card",
            last4: "1002",
            accountIsNew: true,
            period: DateInterval(start: .now.addingTimeInterval(-2_592_000), end: .now),
            transactionsImported: 42,
            duplicatesSkipped: 2,
            categorized: 38,
            uncategorized: 4,
            unreadableRows: 1,
            nothingRecognized: false,
            integrity: .needsReview
        ),
        onDismiss: {},
        onImportAnother: {}
    )
}
