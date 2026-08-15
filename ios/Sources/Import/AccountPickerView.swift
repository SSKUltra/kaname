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
    /// What the person read off the card, when the statement printed too little of it. Held as
    /// text because it is an identifier, not a number: leading zeroes are real, and `0042` is
    /// not forty-two.
    @State private var newAccountLast4: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Not `.secondary`: the system's secondary label sits on the wrong side
                    // of the contrast threshold, and this sentence is the whole reason the
                    // question is being asked.
                    Text(Self.explanation(for: choice))
                        .font(.callout)
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
                                        .foregroundStyle(.primary)
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

                    // Optional, and only ever asked for because the statement itself printed
                    // too few digits to recover — some issuers mask all but the last two. It is
                    // what the person can see on the card in their hand, and without it the
                    // account can never be told apart from another on the same issuer.
                    TextField("Last 4 digits (optional)", text: $newAccountLast4)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                        .onChange(of: newAccountLast4) { _, typed in
                            newAccountLast4 = String(typed.filter(\.isNumber).prefix(4))
                        }
                        .accessibilityLabel("Last four digits of the card, optional")

                    Button("Add account") {
                        onPick(.new(name: trimmedName, last4: statedLast4))
                    }
                    .disabled(trimmedName.isEmpty || !last4IsUsable)
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

    /// Four digits or nothing. A person who has typed one or two has not finished, and
    /// half an identifier is worse than none: it would be stored as though it were read off the
    /// document, and matched against future statements.
    private var last4IsUsable: Bool {
        newAccountLast4.isEmpty || newAccountLast4.count == 4
    }

    private var statedLast4: String? {
        newAccountLast4.count == 4 ? newAccountLast4 : nil
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
