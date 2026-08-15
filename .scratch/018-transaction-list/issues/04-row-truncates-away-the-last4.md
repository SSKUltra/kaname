# 04 — A row truncates away the last-4, so two cards of one product are indistinguishable on screen

**Status:** resolved

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

Evidence: `../evidence/g6-reduce-transparency-menu-vs-rows.png` (the menu reading both
last-4s in full while the rows behind it truncate) and
`../evidence/g7-increase-contrast-dark-mode.png` (the same truncation at the **default** size).

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

---

## Resolution — 2026-08-15, commit `3151e5b`

**Fixed** by option 1, this ticket's own preference: the row leads with the mask.

`TransactionListStrings.accountRowIdentity(name:last4:)` renders `•••• 7742 · <name>`, and
`TransactionRow.accountRowIdentity` is what `TransactionRowView` draws. Trailing truncation is
now spent on the product name — which repeats down the whole column anyway — and the
discriminator sits at the same x on every row, so it can be *scanned* rather than read to the end
of each line. The account line also gained `.monospacedDigit()`, so the digits in that column
line up with each other.

**`accountIdentity` is untouched and still spoken.** The menu, the front door, `ImportedAccounts`
and `accessibilityLabel` all keep the sentence form — this ticket said the VoiceOver label is
correct, and it was not changed. The row is now the one surface whose *drawn* form differs from
its *spoken* form, which is deliberate: a screen reader should hear a sentence and an eye should
scan a column, and both carry the same two facts.

That difference cost one existing assertion its shape. `TransactionAccessibilityTests`'s "every
visible string is inside the announcement" loop can no longer contain the account, because the
two forms are no longer the same string; it now asserts the **facts** — the name and the digits
are in both the drawn line and the announcement, and neither may lose either. The weaker claim is
the honest one, and the stronger claim it replaced was only ever true by coincidence of wording.

**Proof** — `TransactionRowLayoutTests.twoCardsOfOneProductAreToldApartOnScreen`: two accounts
sharing a display name, differing only in `last4`, asserting the drawn lines differ, that each
*starts* with its own mask (difference alone is not enough — `…, endin…` and `…, endin…` also
"differ" from nothing), that their first twelve characters diverge, and that the announcement
still contains the full sentence for each. Watched failing twice:

| Break | Went red |
|---|---|
| `accountRowIdentity` appends the digits last again | *Two cards of the same product render different account lines* (3 issues) |
| the row draws `accountIdentity` again | *The row and the bar draw their decisions…* (the W5 source pin) |

⚠️ **Two loose ends, neither blocking.** The `·` separator is not from the copy deck's
pluralisation-and-honesty apparatus — it is punctuation, and lives in `TransactionListStrings`
with everything else a person reads. And the **default**-size rendering was verified only by
these tests: whether `•••• 7742 · <name>` truncates the name pleasantly on a real screen is a
question for the same manual re-run that closes `02` and `03`.
