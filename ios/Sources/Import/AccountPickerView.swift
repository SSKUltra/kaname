import SwiftUI

/// Which account does this statement belong to?
///
/// Shown only when Kaname genuinely cannot tell — the statement named no card or account
/// number, or more than one account could be the right answer. A deliberately plain dense
/// `List`, not glass: this is a decision about a person's own money, and the rows have to be
/// easy to read and easy to hit, not pretty.
struct AccountPickerView: View {
    let choice: AccountChoice
    let onPick: (AccountDecision) -> Void
    let onCancel: () -> Void

    @State private var newAccountName: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Self.explanation(for: choice))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !choice.candidates.isEmpty {
                    Section("Your accounts") {
                        ForEach(choice.candidates) { candidate in
                            Button {
                                onPick(.existing(id: candidate.id))
                            } label: {
                                LabeledContent {
                                    Text(candidate.last4.map { "•••• \($0)" } ?? "")
                                        .monospacedDigit()
                                } label: {
                                    Text(candidate.name)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Or add a new one") {
                    TextField("Account name", text: $newAccountName)
                        .textInputAutocapitalization(.words)
                    Button("Add account") {
                        onPick(.new(name: trimmedName))
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .navigationTitle("Which account?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                if newAccountName.isEmpty {
                    newAccountName = choice.suggestedName
                }
            }
        }
    }

    private var trimmedName: String {
        newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the person is being asked — stated plainly, and never as an error.
    private static func explanation(for choice: AccountChoice) -> String {
        let issuer = choice.issuerDisplayName
        if let last4 = choice.last4 {
            return "This \(issuer) statement ends in \(last4), which doesn't match any account "
                + "you have. Tell Kaname where it belongs."
        }
        if choice.candidates.isEmpty {
            return "This \(issuer) statement doesn't say which account it's for, and you don't "
                + "have one yet. Name the account it should go into."
        }
        return "This \(issuer) statement doesn't say which account it's for, and you have more "
            + "than one it could be. Pick the right one — Kaname won't guess."
    }
}

#Preview {
    AccountPickerView(
        choice: AccountChoice(
            issuerDisplayName: "Example Bank Account",
            last4: nil,
            candidates: [
                AccountCandidate(id: "1", name: "Everyday", last4: "3425"),
                AccountCandidate(id: "2", name: "Savings", last4: nil),
            ],
            suggestedName: "Example Bank Account"
        ),
        onPick: { _ in },
        onCancel: {}
    )
}
