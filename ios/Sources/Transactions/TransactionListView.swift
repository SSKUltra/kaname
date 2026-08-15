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
    /// The identity that lets the scope button and the clear button *morph* into and out of
    /// one another rather than cross-fading — the filter changing is one control changing
    /// shape, not two controls swapping places.
    @Namespace private var filterChrome

    init(filter: AccountFilter, model: TransactionListViewModel, onImport: @escaping () -> Void) {
        entryFilter = filter
        _model = State(initialValue: model)
        self.onImport = onImport
    }

    var body: some View {
        content
            .navigationTitle(TransactionListStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            // `.safeAreaBar`, not `.safeAreaInset`: the bar owns its own safe-area inset, so
            // the rows above it can always be scrolled clear of it, at any text size.
            .safeAreaBar(edge: .bottom) { filterBar }
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

    // MARK: - The filter chrome

    /// The screen's only glass, on an **opaque** bar.
    ///
    /// The rows above it are never glassed: a person reads figures against an opaque surface,
    /// not through moving material (FR-068, FR-069). The bar is absent entirely when there are
    /// no accounts to choose between — "All accounts" above a screen saying nothing was
    /// imported is a contradiction (design note D3).
    @ViewBuilder
    private var filterBar: some View {
        if model.showsFilterChrome {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    scopeMenu
                    if model.isFiltered {
                        // One action, always in reach, never inside the menu it would have to
                        // be hunted for in (FR-039).
                        Button(TransactionListStrings.clearFilter) {
                            Task { await model.clearFilter() }
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("clear", in: filterChrome)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The hierarchy change is driven by an `await`, not by the tap, so the
                // animation is attached to the state it produces rather than wrapped around
                // the call. With `glassEffectID` in place this is what makes the two buttons
                // morph rather than cross-fade.
                .animation(.smooth(duration: 0.28), value: model.isFiltered)
            }
            .background(.background)
        }
    }

    /// Which account is being shown, and the one tap that changes it — without leaving the
    /// screen, and without losing the person's place in the app (FR-040).
    private var scopeMenu: some View {
        Menu {
            Section(TransactionListStrings.menuHeader) {
                Button(TransactionListStrings.scopeAll) {
                    Task { await model.clearFilter() }
                }
                ForEach(model.availableFilters, id: \.self) { option in
                    Button {
                        Task { await model.setFilter(option) }
                    } label: {
                        Text(
                            TransactionListStrings.accountIdentity(
                                name: option.accountName ?? "", last4: option.accountLast4))
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.scopeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = model.scopeSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.glass)
        .glassEffectID("scope", in: filterChrome)
        // The scope is a fact about what the person is looking at, so it is spoken as a
        // sentence rather than left to be inferred from a button's label (FR-038, SC-014).
        .accessibilityLabel(model.scopeAnnouncement)
        .accessibilityHint(TransactionListStrings.scopeHint)
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
                // Prominent only where it is the screen's one glass element — with no
                // accounts there is no filter bar beneath it (D2). Everywhere else the bar
                // is on screen, and two prominent controls make prominence meaningless.
                if model.emptyActionIsProminent {
                    Button(ImportEmptyStateView.actionTitle, action: onImport)
                        .buttonStyle(.glassProminent)
                } else {
                    Button(ImportEmptyStateView.actionTitle, action: onImport)
                        .buttonStyle(.glass)
                }
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
