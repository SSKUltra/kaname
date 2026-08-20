import KanameCore
import SwiftUI

/// One transaction, laid out so that nothing about the money can be lost to the layout.
///
/// Deliberately **not** `LabeledContent`: that component chooses its own axis, collapses to a
/// two-column shape of its own devising, and renders its value in a secondary style — which is
/// content de-emphasised as decoration (FR-066), and is the exact shape the parked contrast
/// finding on the accounts list is consistent with. The axis here is a decision this app makes
/// and proves (`TransactionRowLayout`), not one it inherits.
struct TransactionRowView: View {
    let row: TransactionRow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: TransactionRowLayout {
        TransactionRowLayout(dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        // The row is the link (R1, FR-003). Its **visual layout does not change**: the
        // indicator a `List` would add is turned off with iOS 26's own API rather than with a
        // hidden-link trick, because a chevron and an inset would silently redo 018's row
        // (R3, FR-046). The tap target is the whole row, which a `List` row already makes
        // ≥44pt tall (R4, FR-062).
        NavigationLink(value: row) {
            rowBody
        }
        .navigationLinkIndicatorVisibility(.hidden)
        // Preserved: the row is still **one** element announcing one sentence (R2, FR-060).
        //
        // ⚠️ What the link does change is the element's *kind*. A combined row used to surface
        // to an automated run as a `StaticText`; as a link it surfaces as a **button** carrying
        // the same sentence — measured, both with this modifier here and with it applied to the
        // link's content, which behave identically. Nothing a person hears moved, and 018's
        // seeded suite still went red, because its helper identified a row by "the first
        // `StaticText` inside the cell". `SeededLaunch` reads the sentence wherever it is now.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint(CategorizeStrings.rowHint)
    }

    private var rowBody: some View {
        Group {
            if layout.axis == .vertical {
                VStack(alignment: .leading, spacing: 6) {
                    details
                    // Last, and full width: at these sizes an amount beside anything else is
                    // an amount with nowhere to go.
                    amount.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    details
                    Spacer(minLength: 8)
                    amount
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.displayDescription)
                .font(.body)
                .lineLimit(layout.descriptionLineLimit)
            // The account this transaction belongs to is content, not decoration: it is what
            // stops a person reading a figure against the wrong account (FR-004, FR-022), so
            // it keeps full contrast and only the smaller size marks it as subordinate. The
            // masked digits lead, because this line gets one line and the digits are the part
            // of it that discriminates (issue 04).
            Text(row.accountRowIdentity)
                .font(.footnote)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(layout.accountNameLineLimit)
            marks
        }
    }

    @ViewBuilder
    private var marks: some View {
        HStack(spacing: 8) {
            Text(row.categoryLabel)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if row.isTransfer {
                // A word and a symbol. Never colour alone (FR-018, FR-071).
                Label(TransactionListStrings.transfer, systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
        }
    }

    private var amount: some View {
        Text(row.formattedAmount)
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(.primary)
            // The amount never yields: it takes the space it needs and the description gives
            // way first. No `minimumScaleFactor`, no truncation mode, no abbreviation —
            // shrinking an amount to fit is truncation with extra steps (FR-021).
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }
}

#Preview {
    List {
        TransactionRowView(
            row: TransactionRow(
                HistoryRow(
                    id: "1",
                    accountId: "a",
                    accountName: "Example Bank Credit Card",
                    accountLast4: "1002",
                    date: "2026-07-15",
                    descriptionRaw: "SYNTHETIC COFFEE SHOP 42",
                    amount: Decimal(string: "450.00") ?? 0,
                    direction: .debit,
                    currency: "INR",
                    categoryName: nil,
                    categoryId: nil,
                    isTransfer: false
                )))
    }
}
