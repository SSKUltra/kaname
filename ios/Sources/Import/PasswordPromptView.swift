import SwiftUI

/// The prompt for a statement's own password.
///
/// A system `.alert` with a `SecureField`, so the password is typed into the platform's own
/// obscured field and nothing else. It is a binding the prompt borrows, never a stored
/// property: the moment the prompt goes away the binding is emptied, so a statement password
/// outlives exactly one unlock attempt and reaches no Keychain item, no store row and no log.
private struct StatementPasswordPrompt: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var password: String
    let message: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Statement password", isPresented: $isPresented) {
                // No `textContentType`: this is the bank's password for one document, not a
                // credential, and the system must never offer to remember it.
                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                Button("Unlock", action: onSubmit)
                Button("Cancel", role: .cancel, action: onCancel)
            } message: {
                Text(message)
            }
            // An alert's content is presented by the system, so its own `onDisappear` is not
            // dependable. The dismissal itself is: whichever way the prompt closed — Unlock,
            // Cancel, or a swipe — the typed password is gone by the next frame.
            .onChange(of: isPresented) { _, presented in
                if !presented {
                    password = ""
                }
            }
    }
}

extension View {
    /// Ask for the password a locked statement needs, without ever keeping it.
    func statementPasswordPrompt(
        isPresented: Binding<Bool>,
        password: Binding<String>,
        message: String,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(
            StatementPasswordPrompt(
                isPresented: isPresented,
                password: password,
                message: message,
                onSubmit: onSubmit,
                onCancel: onCancel
            )
        )
    }
}
