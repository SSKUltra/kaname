import SwiftUI

/// The transaction list: every account's history in one date-ordered sequence.
///
/// A plain `List` of `Section`s — **opaque**, with no material and no glass anywhere near it.
/// Dense rows of figures are read, not decorated, and translucency under scrolling numbers is
/// a legibility tax for no gain (FR-068). `.listStyle(.plain)` is what pins a date heading
/// while the person scrolls through it, so the date they are reading stays on screen (FR-034).
struct TransactionListView: View {
    @State private var model: TransactionListViewModel
    /// The filter this screen was entered with. `.all` from the toolbar, an account from the
    /// front door — applied through the **same** call the in-screen filter makes (FR-037).
    private let entryFilter: AccountFilter
    let onImport: () -> Void

    init(filter: AccountFilter, model: TransactionListViewModel, onImport: @escaping () -> Void) {
        entryFilter = filter
        _model = State(initialValue: model)
        self.onImport = onImport
    }

    var body: some View {
        content
            .navigationTitle(TransactionListStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if entryFilter == .all {
                    await model.onAppear()
                } else {
                    await model.setFilter(entryFilter)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .accessibilityLabel(TransactionListStrings.loadingAnnouncement)
        case .showing:
            rows
        case .empty(let kind):
            emptyState(TransactionListStrings.emptyState(for: kind))
        case .unavailable:
            ContentUnavailableView {
                Label(TransactionListStrings.unavailableTitle, systemImage: "exclamationmark.triangle")
            } description: {
                Text(TransactionListStrings.unavailableMessage)
            } actions: {
                Button(TransactionListStrings.unavailableRetry) {
                    Task { await model.onAppear() }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var rows: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        TransactionRowView(row: row)
                            .task { await model.loadMoreIfNeeded(currentRowID: row.id) }
                    }
                } header: {
                    Text(group.heading)
                        .accessibilityLabel(
                            TransactionListStrings.groupAnnouncement(
                                heading: group.heading, count: group.rows.count))
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func emptyState(_ empty: TransactionListStrings.EmptyState) -> some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: "tray")
        } description: {
            Text(empty.message)
        } actions: {
            switch empty.action {
            case .importStatement:
                // The one prominent element, and only on the state where nothing else on
                // screen is glass.
                Button(ImportEmptyStateView.actionTitle, action: onImport)
                    .buttonStyle(.glassProminent)
            case .clearFilter:
                Button(TransactionListStrings.clearFilter) {
                    Task { await model.clearFilter() }
                }
                .buttonStyle(.glass)
            case nil:
                EmptyView()
            }
        }
    }
}
