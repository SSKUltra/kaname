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
                        LabeledContent {
                            Text(Self.periodText(period))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        } label: {
                            Text("Period")
                        }
                    }
                }

                Section(ImportSummary.importedSectionTitle) {
                    ForEach(summary.importedFigures) { figure($0) }
                }

                // A second heading, because these two count something else. They are the
                // account's whole position, recomputed on every import by design, and under
                // the "Imported" heading they read as an outcome of the document just handed
                // over — four numbers that do not sum
                // (`.scratch/016-statement-import-vertical/issues/05`).
                Section {
                    ForEach(summary.accountFigures) { figure($0) }
                } header: {
                    Text(ImportSummary.accountSectionTitle)
                } footer: {
                    Text(ImportSummary.accountSectionCaption)
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
                // Last, and in the content rather than the toolbar. FR-035 requires that another
                // import can be started from this screen; it does **not** require a chrome
                // button, and as one it cost the screen its title — "Import another" opposite
                // "Done" left the inline title too little width to render, so the first screen
                // after a person's first import read `Import comp…` at the *default* text size
                // (`.scratch/016-statement-import-vertical/issues/06`). As a row it is a next
                // action rather than a control competing with the title, it can wrap at any
                // text size, and it sits **below** the notices, so nothing Kaname could not
                // vouch for is skipped past on the way to importing again.
                Section {
                    Button("Import another statement", action: onImportAnother)
                }
            }
            .navigationTitle("Import complete")
            .navigationBarTitleDisplayMode(.inline)
            // **One** toolbar action, so the title has the width to say what happened.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
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
                .foregroundStyle(.primary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.issuerDisplayName)
                if summary.accountIsNew {
                    // Not `.secondary`: grey at footnote size does not hold contrast, and the
                    // smaller font already reads as subordinate.
                    Text("New account")
                        .font(.footnote)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ figure: ImportSummary.Figure) -> some View {
        LabeledContent {
            // Explicitly primary: `LabeledContent` renders its value in a secondary style,
            // which does not hold contrast for a figure (FR-045, FR-046).
            Text(figure.count.formatted())
                .monospacedDigit()
                .foregroundStyle(.primary)
        } label: {
            Text(figure.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(figure.label): \(figure.count)")
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
