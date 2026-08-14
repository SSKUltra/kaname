import SwiftUI

/// What the person has, once they have anything. A plain dense `List` — never glassed, so
/// the figures are read against an opaque surface rather than through moving material.
///
/// Each row leads to the transaction list, filtered to that account: the same one list, with
/// fewer rows in it, entered through the same `AccountFilter` value the in-screen filter sets.
/// One code path, so a filtered list reached from here and one reached from there cannot come
/// to differ.
struct ImportedAccountsView: View {
    let accounts: [ImportedAccount]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List(accounts) { account in
            NavigationLink(
                value: AccountFilter.account(id: account.id, name: account.name, last4: account.last4)
            ) {
                row(account)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.announcement(for: account))
        }
    }

    /// Deliberately not `LabeledContent`. That component picks its own axis, collapses to a
    /// shape of its own at accessibility sizes, and renders its value in a secondary style a
    /// count this small cannot hold contrast in — which is what the `.foregroundStyle`
    /// override here used to exist to fight. The axis is decided by the same rule the
    /// transaction row uses, and proved by the same test.
    @ViewBuilder
    private func row(_ account: ImportedAccount) -> some View {
        let layout = TransactionRowLayout(dynamicTypeSize: dynamicTypeSize)
        if layout.axis == .vertical {
            VStack(alignment: .leading, spacing: 4) {
                identity(account)
                count(account).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                identity(account)
                Spacer(minLength: 8)
                count(account)
            }
        }
    }

    private func identity(_ account: ImportedAccount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // The account's own name, which is whatever the engine called the issuer
            // when the account was created — the app never knows the bank itself.
            Text(account.name)
                .font(.headline)
            if let last4 = account.last4 {
                // Deliberately not `.secondary`: grey at this size does not hold
                // contrast, and the smaller font is enough to keep it subordinate.
                Text(TransactionListStrings.maskedLast4(last4))
                    .font(.footnote)
                    .monospacedDigit()
            }
        }
    }

    private func count(_ account: ImportedAccount) -> some View {
        Text(account.transactionCount.formatted())
            .monospacedDigit()
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    /// One sentence per account, so VoiceOver reads a fact rather than three loose fragments.
    static func announcement(for account: ImportedAccount) -> String {
        let identity = TransactionListStrings.accountIdentity(name: account.name, last4: account.last4)
        return "\(identity): \(TransactionListStrings.transactionCount(account.transactionCount))"
    }
}

#Preview {
    NavigationStack {
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
}
