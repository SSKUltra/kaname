import Foundation
import KanameCore
import Testing

@testable import Kaname

// The doubles and fixtures the transaction list's unit suites share.
//
// One copy, at file scope, because two copies of a fixture are how two suites come to
// disagree about what they are fixtures of — and because the suites that use them are split
// by subject (paging, headings) rather than by what they need to build.

/// A `TransactionHistoryReading` that serves scripted pages and can be held open, so
/// "two calls before the first returns" is a fact the test controls rather than a race
/// it hopes for.
struct PageRequest: Equatable, Sendable {
    let accountID: String?
    let cursor: HistoryCursor?
    let limit: UInt32
}

actor HistoryDouble: TransactionHistoryReading {
    private let pages: [HistoryPage]
    private let summaries: [AccountSummary]
    private var served = 0
    private var isPaused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [PageRequest] = []

    init(pages: [HistoryPage], summaries: [AccountSummary] = []) {
        self.pages = pages
        self.summaries = summaries
    }

    var requestCount: Int { requests.count }

    func pause() { isPaused = true }

    func release() {
        isPaused = false
        let held = waiters
        waiters = []
        for waiter in held { waiter.resume() }
    }

    func page(accountID: String?, cursor: HistoryCursor?, limit: UInt32) async throws -> HistoryPage {
        requests.append(PageRequest(accountID: accountID, cursor: cursor, limit: limit))
        if isPaused {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        defer { served += 1 }
        return served < pages.count ? pages[served] : HistoryPage(rows: [], cursor: nil)
    }

    func accountSummaries() async throws -> [AccountSummary] { summaries }
}

let listClock: @Sendable () -> Date = {
    Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-16, inside the corpus's dates.
}

func historyRow(
    _ id: String,
    _ date: String,
    _ amount: String = "10.00",
    accountID: String = "account-1",
    accountName: String = TransactionCorpus.everyday
) -> HistoryRow {
    HistoryRow(
        id: id,
        accountId: accountID,
        accountName: accountName,
        accountLast4: "1123",
        date: date,
        descriptionRaw: "SYNTHETIC ROW \(id)",
        amount: TransactionCorpus.decimal(amount),
        direction: .debit,
        currency: "INR",
        categoryName: nil,
        categoryId: nil,
        isTransfer: false
    )
}

/// The headings one screenful produces, read at a given "now".
func headings(
    for rows: [HistoryRow],
    clock: @escaping @Sendable () -> Date
) async throws -> [String] {
    let double = HistoryDouble(
        pages: [HistoryPage(rows: rows, cursor: nil)],
        summaries: [accountSummary(UInt32(rows.count))]
    )
    let model = await TransactionListViewModel(history: double, clock: clock)
    await model.onAppear()
    return await model.groups.map(\.heading)
}

func historyCursor(_ sequence: Int64) -> HistoryCursor {
    HistoryCursor(
        marks: [AccountMark(accountId: "account-1", date: "2026-07-10", sequence: sequence)])
}

func accountSummary(_ count: UInt32, onlyExcluded: Bool = false) -> AccountSummary {
    AccountSummary(
        id: "account-1",
        name: TransactionCorpus.everyday,
        last4: "1123",
        isCreditCard: false,
        currency: "INR",
        liveTransactionCount: count,
        hasOnlyExcludedRows: onlyExcluded
    )
}
