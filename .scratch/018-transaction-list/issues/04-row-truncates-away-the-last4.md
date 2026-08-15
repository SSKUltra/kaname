# 04 — A row truncates away the last-4, so two cards of one product are indistinguishable on screen

**Status:** ready-for-agent

**Found:** 2026-08-15, on the simulator, during the manual gate, with the perf corpus imported —
which holds **two** `ICICI_AMAZONPAY_CARD` accounts (`····1002` and `····7742`).
**Belongs to:** `018-transaction-list` — `TransactionRowView` and
`TransactionListModels.accountNameLineLimit`.
**Severity:** A person cannot tell which of two cards a transaction belongs to. On a screen whose
entire premise is one combined list across accounts, that is the screen's own job failing.

## What is on screen

At the **default** text size a row's account line reads:

```
ICICI Amazon Pay Credit Card, endin…
HDFC Swiggy Credit Card, ending 90…
```

The row renders `accountIdentity` — `"\(name), ending \(last4)"` — with
`accountNameLineLimit = 1` (`TransactionListModels.swift:218`). The last-4 is appended **last**,
so trailing truncation removes precisely the only part that discriminates. With two ICICI Amazon
Pay cards imported, every row of both reads `ICICI Amazon Pay Credit Card, endin…`.

`ending 90…` is worse still: it looks like a number and is not one.

Evidence: session screenshots `g6.png` (menu vs rows, side by side) and `g7.png`.

## The asymmetry that makes this clearly a defect

The app **has** the last-4 and uses it everywhere else:

| Surface | Renders | Verified |
|---|---|---|
| Scope menu | `ICICI Amazon Pay Credit Card, ending 7742` | ✅ in full, both cards distinct |
| VoiceOver row label | `…, ₹2,490.08 debit, ICICI Amazon Pay Credit Card, ending 7742, …` | ✅ via Accessibility Inspector |
| Filter chip | `ICICI Amazon Pay Cr…` / `···· 7742` | ✅ at default size |
| **The row** | `ICICI Amazon Pay Credit Card, endin…` | ❌ |

So a **VoiceOver user can tell the two cards apart and a sighted user cannot.** That is the
inversion of the usual failure and it is not a deliberate trade — nothing in `spec.md`,
`plan.md` or `research.md` argues for dropping the digits from the row.

## The fix

`lineLimit(1)` on the account line is reasonable; appending the discriminator to a
trailing-truncated string is not. Options, in preference order:

1. **Lead with the mask**: `···· 7742 · ICICI Amazon Pay Credit Card`. Truncation then eats the
   product name, which repeats down the whole column anyway, and keeps the digits.
2. `.truncationMode(.middle)` on the existing string — cheapest change, keeps both ends.
3. Render the last-4 as its own non-truncating element beside the name.

Whichever is chosen, the VoiceOver label must keep its current sentence form; it is correct.

## How to prove it

A test over two accounts that share a display name and differ only in `last4`, asserting the two
rows render **different** account lines. It must be watched failing against today's row before it
is trusted — a single-account fixture passes either way.
