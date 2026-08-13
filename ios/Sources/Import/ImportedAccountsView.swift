import SwiftUI

/// What the person has, once they have anything. A plain dense `List` — never glassed, so
/// the figures are read against an opaque surface rather than through moving material.
struct ImportedAccountsView: View {
    let accounts: [ImportedAccount]

    var body: some View {
        List(accounts) { account in
            LabeledContent {
                // Explicitly primary: `LabeledContent` renders its value in a secondary
                // style, which does not hold contrast for a figure this small.
                Text(account.transactionCount.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    // The account's own name, which is whatever the engine called the issuer
                    // when the account was created — the app never knows the bank itself.
                    Text(account.name)
                        .font(.headline)
                    if let last4 = account.last4 {
                        // Deliberately not `.secondary`: grey at this size does not hold
                        // contrast, and the smaller font is enough to keep it subordinate.
                        Text("•••• \(last4)")
                            .font(.footnote)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.announcement(for: account))
        }
    }

    /// One sentence per account, so VoiceOver reads a fact rather than three loose fragments.
    static func announcement(for account: ImportedAccount) -> String {
        let identity = account.last4.map { "\(account.name), ending \($0)" } ?? account.name
        let count = account.transactionCount
        return "\(identity): \(count) \(count == 1 ? "transaction" : "transactions")"
    }
}

#Preview {
    ImportedAccountsView(accounts: [
        ImportedAccount(
            // Deliberately not a real bank: the app renders whatever name the engine gave the
            // account, and never knows which issuers exist.
            id: "1",
            name: "Example Bank Credit Card",
            last4: "1002",
            isCreditCard: true,
            transactionCount: 42
        )
    ])
}
