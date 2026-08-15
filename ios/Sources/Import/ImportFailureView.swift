import SwiftUI

/// The single terminal screen for every way an import can fail: a symbol, one hand-written
/// sentence, and a way back. It renders only the copy deck — never an error's own text.
struct ImportFailureView: View {
    let failure: ImportFailure
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: failure.symbolName)
        } description: {
            Text(failure.message)
        } actions: {
            Button("Try another file", action: onRetry)
                .prominentAction()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Unrecognized") {
    ImportFailureView(failure: .unrecognizedIssuer) {}
}

#Preview("Scan") {
    ImportFailureView(failure: .noExtractableText) {}
}
