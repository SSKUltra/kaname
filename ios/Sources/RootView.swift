import KanameCore
import SwiftUI
import UniformTypeIdentifiers

/// Root screen: the minimal real import flow — one action, the system document picker, and
/// the summary of what landed. US7 replaces this with the full first-run empty state.
struct RootView: View {
    /// Human-readable engine build, sourced live from `kaname-core` via UniFFI — the
    /// single source of truth for the version (never hardcoded in the app).
    var versionLabel: String { "Engine v\(engineVersion())" }

    @State private var model = ImportViewModel()
    @State private var isPickingFile = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Kaname")
                .safeAreaInset(edge: .bottom) { bottomBar }
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
        .alert("Statement password", isPresented: $model.isPromptingForPassword) {
            SecureField("Password", text: $model.passwordEntry)
            Button("Unlock") { Task { await model.submitPassword() } }
            Button("Cancel", role: .cancel) { model.reset() }
        } message: {
            Text(model.passwordPromptMessage ?? ImportFailure.passwordRequired.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let failure = model.failure {
            ImportFailureView(failure: failure) {
                model.reset()
                isPickingFile = true
            }
        } else {
            ContentUnavailableView(
                "Kaname",
                systemImage: "key.fill",
                description: Text("The key to your money. On-device, private by design.")
            )
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.isRunning {
                progress
            } else if model.failure == nil {
                Button("Import a statement") { isPickingFile = true }
                    .buttonStyle(.glassProminent)
            }
            // Show the engine version only when present — never fabricate one.
            if !engineVersion().isEmpty {
                Text(versionLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Engine version \(engineVersion())")
            }
        }
        .padding(.bottom, 8)
    }

    private var progress: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                Text(Self.stageText(model.stage))
                Button("Cancel") { Task { await model.cancel() } }
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityElement(children: .contain)
    }

    private var showingSummary: Binding<Bool> {
        Binding(get: { model.summary != nil }, set: { if !$0 { model.reset() } })
    }

    static func stageText(_ stage: ImportStage?) -> String {
        switch stage {
        case .reading, nil: return "Reading the statement…"
        case .identifying: return "Working out who issued it…"
        case .parsing: return "Reading the transactions…"
        case .checking: return "Checking the figures…"
        case .saving: return "Saving to your device…"
        case .categorizing: return "Sorting into categories…"
        }
    }
}

#Preview {
    RootView()
}
