import KanameCore
import SwiftUI
import UniformTypeIdentifiers

/// Root screen: the minimal real import flow — one action, the system document picker, and
/// the summary of what landed. US7 replaces this with the full first-run empty state.
struct RootView: View {
    @State private var model = ImportViewModel()
    @State private var isPickingFile = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Kaname")
                .safeAreaInset(edge: .bottom) { bottomBar }
                .task { await model.refreshAccounts() }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            // Backing out of the picker is not a failed import; it leaves the app as it was.
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await model.importStatement(at: url) }
        }
        .sheet(isPresented: showingSummary) {
            if let summary = model.summary {
                ImportSummaryView(summary: summary) {
                    model.reset()
                } onImportAnother: {
                    model.reset()
                    isPickingFile = true
                }
            }
        }
        .sheet(isPresented: showingAccountPicker) {
            if let choice = model.accountChoice {
                AccountPickerView(choice: choice) { decision in
                    Task { await model.chooseAccount(decision) }
                } onCancel: {
                    Task { await model.cancel() }
                    model.reset()
                }
            }
        }
        .statementPasswordPrompt(
            isPresented: $model.isPromptingForPassword,
            password: $model.passwordEntry,
            message: model.passwordPromptMessage ?? ImportFailure.passwordRequired.message,
            onSubmit: { Task { await model.submitPassword() } },
            onCancel: { model.reset() }
        )
    }

    @ViewBuilder
    private var content: some View {
        if let failure = model.failure {
            ImportFailureView(failure: failure) {
                model.reset()
                isPickingFile = true
            }
        } else if model.accounts.isEmpty {
            // A fresh install: the front door explains itself, and its own button is the one
            // tap that opens the picker — so the bottom bar adds nothing here.
            ImportEmptyStateView { isPickingFile = true }
        } else {
            ImportedAccountsView(accounts: model.accounts)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if model.isRunning {
            ImportProgressView(stage: model.stage) {
                Task { await model.cancel() }
            }
            .padding(.bottom, 8)
        } else if model.failure == nil && !model.accounts.isEmpty {
            // Import stays one tap away once there is data to come back to; the empty state
            // carries its own action, and two prominent buttons would be one too many. The
            // bar is opaque for the same reason it is on the empty state: a glass label over
            // a scrolling list of rows is where contrast goes.
            Button("Import a statement") { isPickingFile = true }
                .buttonStyle(.glassProminent)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.background)
        }
    }

    private var showingSummary: Binding<Bool> {
        Binding(get: { model.summary != nil }, set: { if !$0 { model.reset() } })
    }

    private var showingAccountPicker: Binding<Bool> {
        Binding(
            get: { model.accountChoice != nil },
            set: { presented in
                // Swiping the question away abandons the import; nothing was written for it.
                if !presented {
                    Task { await model.cancel() }
                    model.reset()
                }
            }
        )
    }
}

#Preview {
    RootView()
}
