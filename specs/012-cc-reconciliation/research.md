# Phase 0 — Research: Credit-Card Statement Reconciliation (the CC counterpart to the shipped bank-ledger balance-chain; zero new deps)

**Feature**: `012-cc-reconciliation` | **Date**: 2026-07-19
**Method**: The web engine is the source of truth. Its reconciliation module
(`finance-tracker-phase/backend/app/services/ingestion/reconciliation.py`, the `reconcile` function),
its unit tests (`test_reconciliation.py`), the integration tests (`test_statement_reconciliation.py`),
and the two readers' printed-total scrapes (`yes_kiwi.py`, `iob.py`) were **read as ground truth**. The
three **new** regexes this slice introduces (Yes `DEBITS_RE`/`CREDITS_RE`, IOB `SUMMARY_RE`) were
**verified against the real `regex` + `rust_decimal` crates** (a throwaway integration test on the
pinned stable toolchain, exercising the exact fixture `full_text`, removed after use — repo left clean).
Every decision below is a faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was **locked by the requester** and confirmed here
with evidence. **Headline finding: reconciliation requires no new dependency and no new shared helper —
it is the credit-card analogue of `balance_chain.rs`, delivered as one new check module + two
`ParsedStatement` fields + two reader enrichments + fixtures + one bridge export + a Swift test. The
only non-mechanical decisions are the three-way outcome typing (D2), the typed audit-detail record (D3),
and the `printed_total_spend` carve-out (D9).**

---

## D1 — Reuse the landed foundations wholesale; add `reconcile.rs` as the CC counterpart to `balance_chain.rs`

**Decision**: Add `statement/reconcile.rs` (mirroring the web `reconciliation.py`) **beside**
`statement/balance_chain.rs`, and touch nothing structural elsewhere. Reconciliation **reuses,
unchanged**: `ParsedStatement`/`ParsedTransaction`/`Direction` (`base.rs`/`model.rs`), the
`rust_decimal::Decimal` money type + the `Decimal::new(100, 2)` tolerance idiom (from `balance_chain`),
the parity harness (`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`
custom type), and the privacy-egress gate + CI. It is structured **identically to `balance_chain.rs`**:
a status enum + a typed result record + a single `pub fn` over `&ParsedStatement`, with a module
comment. The one FFI export lives in `ffi.rs`, as `check_balance_chain` does.

**Rationale**: The bank-ledger slices (007–010) built and proved this "pure check over the shared
statement → typed result across the bridge" shape. Reconciliation is its credit-card twin and slots
into the same seams; mirroring `reconciliation.py → reconcile.rs` next to `balance_chain.rs` keeps the
port a mechanical, reviewable diff and closes out the per-statement reconciliation layer (FR-016).

**Alternatives**: Rebuild any shared helper, or invent a new result-delivery mechanism — rejected:
violates FR-016 ("no new shared engine helper beyond the reconciliation check and the two printed-total
fields") and the "reuse, not rebuild" assumption; risks parity drift.

---

## D2 — Three-way outcome typed as `status: Option<ReconcileStatus>` with a **two-variant** enum

**Decision**: `pub enum ReconcileStatus { Reconciled, NeedsReview }`
(`#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]`), carried in the result as
**`status: Option<ReconcileStatus>`**. **`None` is the neutral "no balance" outcome**, explicitly
distinct from `Some(NeedsReview)`. This mirrors the web engine's `status: str | None`
(`"reconciled"` / `"needs_review"` / a neutral `None`) exactly.

**Rationale**: FR-004/US3/SC-006 make the neutral outcome a **hard, non-conflatable** third state ("we
couldn't check", not "we checked and it's wrong"). An `Option` of a two-variant enum makes the neutral
state `None` — **structurally impossible** to compare equal to `Some(NeedsReview)` — and is a faithful
1:1 map of the web `str | None`. It also mirrors `balance_chain`'s use of an `Option` for the
empty-statement neutral shape (`reason: Some(...)`), keeping the two checks idiomatically consistent.

**Alternatives**:
- A **three-variant** enum `{ Reconciled, NeedsReview, NoBalance }` — rejected: it folds the neutral
  "unknown" into the same type-space as the two real verdicts, making `NoBalance == NeedsReview` a
  *possible* comparison a caller might accidentally treat as "a verdict"; the spec's Assumptions
  explicitly leave this a plan decision and the web engine's `None` maps most faithfully to `Option`.
- A boolean + side flag — rejected: loses the clean 1:1 with the web `str | None` and is easy to
  misuse.

---

## D3 — Typed audit-detail record `ReconcileResult` (mirrors `ChainResult`, not a dynamic dict)

**Decision**: `pub struct ReconcileResult` (`#[derive(Debug, Clone, PartialEq, uniffi::Record)]`) with
**typed fields** mirroring the web `detail` dict (the same pattern `ChainResult` uses instead of a
dynamic dict):

| Field | Type | Set on | Meaning |
|---|---|---|---|
| `status` | `Option<ReconcileStatus>` | always | `Some(Reconciled)` / `Some(NeedsReview)` / `None` (neutral) — D2 |
| `read_debits` | `Decimal` | **always** | Σ `line.amount` where `direction == Debit` |
| `read_credits` | `Decimal` | **always** | Σ `line.amount` where `direction == Credit` |
| `printed_debits` | `Option<Decimal>` | primary | the printed debit total compared (echoed from the statement) |
| `printed_credits` | `Option<Decimal>` | primary | the printed credit total compared |
| `expected_balance_change` | `Option<Decimal>` | fallback | `closing − opening` |
| `computed_balance_change` | `Option<Decimal>` | fallback | `read_debits − read_credits` |
| `reason` | `Option<String>` | neutral | `Some("no printed totals extracted")` |

**Rationale**: FR-010 requires an audit detail "sufficient to explain the verdict" for each tier. A
dynamic Python dict does not cross UniFFI cleanly and loses type safety; `ChainResult` already
established the "typed record echoing the detail payload" pattern for the shipped balance-chain, so
reconciliation uses the same. `read_debits`/`read_credits` are **always** populated (the edge case "only
one printed total present … the read sums for both directions are still recorded" — spec Edge Cases,
FR-010); the tier-specific fields are `None` on the paths that don't apply.

**Alternatives**: A single opaque `detail: String` (JSON) — rejected: opaque to Swift, not
value-comparable in tests, and diverges from the shipped `ChainResult` precedent.

---

## D4 — Tolerance = `Decimal::new(100, 2)` (= 1.00), inclusive — the SAME constant as `balance_chain`

**Decision**: `let tolerance = Decimal::new(100, 2);` — literally `1.00`, an **exact** `Decimal`, the
same construction `balance_chain::check` uses (`balance_chain.rs:90`). Every comparison is
`(read − printed).abs() <= tolerance` (and, in the fallback, `(computed − expected).abs() <=
tolerance`): a difference of **exactly ₹1.00 is within tolerance**; strictly greater is not.

**Rationale**: FR-006/US1/SC-004 pin the ₹1.00 rounding tolerance and its **inclusive** boundary; the
web `reconcile` uses `abs(...) <= Decimal("1.00")`. Reusing the identical `Decimal::new(100, 2)` idiom
keeps the two checks consistent and keeps money exact (never `f64`, FR-017).

**Verified** (against the real `rust_decimal`): `Decimal::new(100, 2) == Decimal::from_str("1.00")`, and
the `<=` boundary holds at exactly `1.00`. `(read - printed).abs()` on the ground-truth sums is `0.00`
for both Yes and IOB (well within tolerance).

**Alternatives**: A float tolerance or a `>` (exclusive) comparison — rejected: floats violate FR-017;
`>` would misclassify the exact-₹1.00 boundary (SC-004 asserts 0 misclassifications there).

---

## D5 — `read_debits` / `read_credits`: sums over ALL rows by the row's own direction; empty ⇒ 0.00

**Decision**: `read_debits = Σ line.amount where line.direction == Direction::Debit`;
`read_credits = Σ line.amount where line.direction == Direction::Credit`, iterating **all**
`statement.lines`. With no rows, each sum is `Decimal::ZERO`-valued at `0.00` (an empty fold). Direction
is read from `line.direction` (already decided by the reader from the statement's `Dr`/`Cr` marker) —
**never** re-derived from the amount's sign (FR-002).

**Rationale**: FR-002 requires the sums over **all** parsed rows (not a deduped subset), as exact
decimals, with an empty set summing to 0.00. The check is **read-only** — it reads `line.amount` /
`line.direction` and never mutates, drops, or reorders a row (FR-003/US5/SC-009), so a NEEDS_REVIEW
statement still reports every row afterward. Amounts are non-negative `Decimal` (readers strip sign;
polarity is the direction), so the sums are straightforward.

**Traced against the ground truth**:
- Yes rows: `Credit 9000.00`, `Debit 100.00` → `read_debits = 100.00`, `read_credits = 9000.00`.
- IOB rows: `Credit 1000.00`, `Debit 3500.00` → `read_debits = 3500.00`, `read_credits = 1000.00`.
- Empty statement → `read_debits = 0.00`, `read_credits = 0.00` (no panic).

**Alternatives**: Deriving direction from amount sign — rejected: violates FR-002 and the constitution's
"polarity is explicit, never amount sign" rule.

---

## D6 — Primary tier: printed totals present ⇒ per-side ₹1.00 check; absent total not required

**Decision**: If `printed_total_debits.is_some() || printed_total_credits.is_some()` → **primary path**.
For each present total, check `(read − printed).abs() <= tolerance`; the verdict is
`Some(Reconciled)` **iff every present total passes**, else `Some(NeedsReview)`. Fill
`printed_debits`/`printed_credits` (echoing the statement's totals); leave the fallback fields and
`reason` `None`. **The opening→closing fallback is never consulted when any printed total is present**
(FR-005, SC-008).

**Rationale**: FR-005/006/007 + US1 + the spec Edge Cases: "Only one printed total present" → only that
side is checked (the absent side is not required, but both `read_*` sums are still recorded via D3);
"Both printed totals present, one matches and one does not" → **NEEDS_REVIEW** (every present total must
pass). "Zero read rows with printed totals present" → the read sums are 0.00 and the verdict is
RECONCILED only if each present total is itself within ₹1.00 of 0.00.

**Traced**:
- Yes: `printed_debits 100.00` vs `read_debits 100.00` (0.00 ≤ 1.00 ✓); `printed_credits 9000.00` vs
  `read_credits 9000.00` (✓) → **RECONCILED**.
- IOB: `printed_debits 3500.00` vs `3500.00` (✓); `printed_credits 1000.00` vs `1000.00` (✓) →
  **RECONCILED**.
- Mismatch (printed debit `9999`): `(100.00 − 9999).abs() = 9899.00 > 1.00` → **NEEDS_REVIEW**, with
  `read_debits`/`read_credits`/`printed_debits`/`printed_credits` all recorded.

**Alternatives**: Requiring both totals to be present — rejected: FR-007 makes an absent total "not
required"; each side is independent.

---

## D7 — Fallback tier: both opening & closing present ⇒ balance-change check within ₹1.00

**Decision**: Else if `printed_opening_balance.is_some() && printed_closing_balance.is_some()` →
**fallback path**. `expected = closing − opening`; `computed = read_debits − read_credits`; the verdict
is `Some(Reconciled)` iff `(computed − expected).abs() <= tolerance`, else `Some(NeedsReview)`. Fill
`expected_balance_change`/`computed_balance_change`; leave `printed_debits`/`printed_credits` and
`reason` `None`. (Debits raise the balance owed; credits lower it — so the read change is
`Σdebits − Σcredits` and the printed change is `closing − opening`; a negative change compares just like
a positive one.)

**Rationale**: FR-008 + US4. This is the second tier of the pinned ladder, ported for byte-for-byte
parity and for any future reader that prints balances rather than category totals. No shipped credit-card
reader currently populates opening/closing balances, so the fallback is exercised via a **constructed**
statement (as the web unit test does) — a `reconcile.rs` unit test, not a fixture.

**Traced** (from the web `test_reconciliation.py` / spec US4-AC1): debit `500.00` + credit `200.00`
(read change `+300.00`), opening `1000.00`, closing `1300.00` (printed change `+300.00`) →
`(300.00 − 300.00).abs() = 0.00 ≤ 1.00` → **RECONCILED**, `expected_balance_change = +300.00`,
`computed_balance_change = +300.00`. Perturb closing beyond ₹1.00 → **NEEDS_REVIEW**.

**Alternatives**: Using the fallback when only one balance is present — rejected: FR-009 requires
**both**; with one (or neither) the outcome is neutral (D8).

---

## D8 — Neutral tier: no printed totals and not both balances ⇒ `status: None` + reason

**Decision**: Else → **neutral**: `status: None`, `reason: Some("no printed totals extracted")`,
`read_debits`/`read_credits` still set, all other fields `None`. This is the outcome for a statement
that prints no per-statement totals and does not print both an opening and a closing balance — including
the four no-total credit-card readers (ICICI, HDFC, SBI, Federal/Scapia).

**Rationale**: FR-004/009 + US3 + SC-006. The neutral outcome is an **"unknown"**, never a **"mismatch"**
— represented as `None` (D2) so it can never equal `Some(NeedsReview)`. The exact reason string
`"no printed totals extracted"` mirrors the web engine's neutral `detail` payload (FR-010).

**Traced**: an ICICI statement (no printed totals, no opening/closing pair) → `status == None`,
`reason == Some("no printed totals extracted")`, `read_debits`/`read_credits` from its rows. Verified in
the parity test `statement_without_printed_totals_is_neutral` (loads `icici/credit_card/basic.json`).

**Alternatives**: Returning `Some(NeedsReview)` when totals are missing — rejected: the exact conflation
FR-004 forbids; it would falsely alarm every no-total statement.

---

## D9 — Two new `ParsedStatement` fields; **`printed_total_spend` deliberately NOT added**

**Decision**: Add to `ParsedStatement` (`base.rs`), **after `printed_closing_balance`**, two fields —
`pub printed_total_debits: Option<Decimal>` and `pub printed_total_credits: Option<Decimal>` — both
defaulting to `None` in `ParsedStatement::new`. **Do NOT add `printed_total_spend`** (the web engine has
it but nothing in reconciliation uses it — an intentional carve-out, consistent with `base.rs`'s "only
the fields this slice needs" doctrine). Update the module doc-comment, which currently says the
reconciliation `printed_*` totals "arrive with a later slice" — that later slice is **now**.

**Rationale**: FR-011 requires the model to gain printed **debit-total** and **credit-total** fields
(each absent when a reader prints none); the opening/closing balance fields the fallback needs **already
exist** (from the bank-ledger work) and are reused. `printed_total_spend` is never read by `reconcile`,
so adding it would ship dead surface — excluded per the same discipline that kept these two fields out
until the slice that needs them (this one). Defaulting both to `None` in the one constructor means all
ten readers and every existing fixture are unaffected; only Yes + IOB populate them.

**Alternatives**: Add all three web fields — rejected: `printed_total_spend` has no consumer (plan
Complexity Tracking). Thread the totals as a side-channel — rejected: fragments the model; two
`Option<Decimal>` fields mirroring `printed_opening/closing_balance` is the minimal, consistent
extension.

---

## D10 — Yes reader enrichment: `DEBITS_RE` + `CREDITS_RE`, populated in `enrich` — **VERIFIED**

**Decision**: Add two `LazyLock<Regex>` statics to `yes.rs` (Rust-escaped ports of `yes_kiwi.py`) and
populate the new fields in `enrich`:

```text
DEBITS_RE  = (?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr
CREDITS_RE = (?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr
```

In `enrich`: `statement.printed_total_debits = DEBITS_RE.captures(full_text).and_then(|c|
parse_amount(&c[1]))` (and `printed_total_credits` from `CREDITS_RE`). The `[^\n]*?` (no newline) means
a total is surfaced **only** when its label and value are on the **same extracted line**; otherwise the
capture fails and the field stays `None` (FR-012, US2-AC3). Rewrite the module-doc paragraph that
currently says printed totals are "out of scope for this slice and are intentionally not ported" → they
are now **surfaced for reconciliation**. Add a reader unit test asserting the totals on the extended
sample.

**Verified against the real `regex` + `rust_decimal`** (throwaway test on the exact extended
`full_text`): `DEBITS_RE` → `"100.00"` → `parse_amount` → `100.00`; `CREDITS_RE` → `"9,000.00"` →
`parse_amount` (strips the thousands separator) → `9000.00`. The two transaction rows
(`… 9,000.00 Cr`, `… 100.00 Dr`) do **not** contain the `Purchases … Rs … Dr` / `Payment & Credits
Received … Rs … Cr` label shapes, so only the two new summary lines match. Matches the web engine's
`printed_total_debits = 100.00`, `printed_total_credits = 9000.00`.

**Alternatives**: A single combined regex, or scraping the transaction rows — rejected: the two-label
scrape is the faithful `yes_kiwi.py` port; the `[^\n]*?` same-line guard is what makes an absent label
leave the field `None` (FR-012).

---

## D11 — IOB reader enrichment: `SUMMARY_RE` (`(?is)`), populated in `enrich` — **VERIFIED**

**Decision**: Add one `LazyLock<Regex>` static to `iob.rs` (port of `iob.py` `_SUMMARY_RE`,
`IGNORECASE|DOTALL` → `(?is)`) and populate the new fields in `enrich`:

```text
SUMMARY_RE = (?is)ACCOUNT SUMMARY\b.*?(?P<prev>[\d,]+(?:\.\d+)?)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+(?P<fees>[\d,]+(?:\.\d+)?)\s+(?P<total>[\d,]+(?:\.\d+)?)
```

In `enrich`: set `printed_total_credits` from group `credits` (the **2nd** figure) and
`printed_total_debits` from group `debits` (the **3rd** figure) — note the order: IOB's summary row is
`Previous | Payment/Credits | Purchases/Debits | Fees | Total`, so **credits precedes debits**. The
`(?is)` makes `.*?` span newlines lazily from `ACCOUNT SUMMARY` to the values row. Rewrite the module-doc
carve-out paragraph. Add a reader unit test (the existing fixture `full_text` already carries the
`ACCOUNT SUMMARY` block).

**Verified against the real `regex` + `rust_decimal`** (throwaway test on the existing IOB fixture
`full_text`): the values row `345.50 1,000.00 3,500.00 0 2,845.50` binds
`prev="345.50"`, `credits="1,000.00"`, `debits="3,500.00"`, `fees="0"`, `total="2,845.50"` →
`printed_total_credits = 1000.00`, `printed_total_debits = 3500.00`. The lazy `.*?` skips the header
line (`Previous Balance Payment / Credits …`, no digits) and the `- + + =` row (no digits) and anchors on
the first row bearing five space-separated numeric tokens whose 2nd and 3rd have exactly 2dp. Matches the
web engine's `printed_total_credits = 1000.00`, `printed_total_debits = 3500.00`.

**Alternatives**: Splitting the values row by whitespace and indexing — rejected: the single anchored
regex is the faithful `iob.py` port and robustly skips the label/legend rows; DOTALL is required so the
match spans from `ACCOUNT SUMMARY` down to the values row.

---

## D12 — Wiring: `mod.rs`, `ffi.rs`, `lib.rs` — one bridge export mirroring `check_balance_chain`

**Decision**:
- `statement/mod.rs` — add `pub mod reconcile;` (near `polarity`/`sbi`, keeping the alphabetical-ish
  order). No extra re-export needed beyond the existing `base::` re-exports.
- `ffi.rs` — add, mirroring `check_balance_chain`:
  ```rust
  use crate::statement::reconcile::{reconcile, ReconcileResult};

  #[uniffi::export]
  pub fn reconcile_statement(statement: ParsedStatement) -> ReconcileResult {
      reconcile(&statement)
  }
  ```
- `lib.rs` — add `reconcile_statement` to the `pub use ffi::{…}` list and
  `pub use statement::reconcile::{ReconcileResult, ReconcileStatus};`.

**Rationale**: FR-019 requires the check reachable over the existing UniFFI bridge "mirroring how the
balance-chain check is exposed". `check_balance_chain(statement: ParsedStatement) -> ChainResult` is the
exact precedent; `reconcile_statement` copies its shape (takes the statement by value, delegates to the
`&`-borrowing pure `reconcile`). The `Decimal` custom-type bridge and `ParsedStatement` record are
reused; the new `ReconcileResult`/`ReconcileStatus` derive `uniffi::Record`/`uniffi::Enum` so bindgen
emits their Swift types.

**Alternatives**: A method on a UniFFI object, or a free function returning a tuple — rejected:
diverges from the shipped `check_balance_chain` free-function-returning-a-record precedent.

---

## D13 — Fixtures + parity harness: extend Yes/IOB, reuse ICICI as the neutral vector, add 3 reconcile tests

**Decision**:
- `fixtures/yes/credit_card/basic.json` — extend `full_text` with two lines **after** "Statement
  Period:": `Current Purchases / Cash Advance & Other Charges : Rs. 100.00 Dr` and
  `Payment & Credits Received : Rs. 9,000.00 Cr`. Add to `expected`: `printed_total_debits: "100.00"`,
  `printed_total_credits: "9000.00"`. Rows/period/last4 unchanged; `_comment` updated.
- `fixtures/iob/credit_card/basic.json` — **no `full_text` change** (already carries the `ACCOUNT
  SUMMARY` block). Add to `expected`: `printed_total_debits: "3500.00"`, `printed_total_credits:
  "1000.00"`; `_comment` updated.
- `tests/parity.rs` — extend `Expected` with `#[serde(default)] printed_total_debits: Option<String>`
  and `printed_total_credits: Option<String>`, and assert them in `assert_matches_expected` via the
  existing `parse_dec` closure. All other CC fixtures **omit** them → `None` (unchanged behaviour, like
  the existing `printed_opening/closing_balance` assertions). Add three reconcile parity tests using
  `reconcile_statement` + `ReconcileStatus`:
  - `yes_statement_reconciles` → `status Some(Reconciled)`, `read_debits 100.00`, `read_credits
    9000.00`, `printed_debits 100.00`, `printed_credits 9000.00`.
  - `iob_statement_reconciles` → `read_debits 3500.00`, `read_credits 1000.00`, printed totals match,
    `status Some(Reconciled)`.
  - `statement_without_printed_totals_is_neutral` → load `icici/credit_card/basic.json`, reconcile →
    `status == None`, `reason == Some("no printed totals extracted")`.

**Rationale**: FR-024/025 + US7 pin all three verdicts against golden vectors; the extended Yes/IOB
vectors prove the primary path end-to-end (read → reconcile → RECONCILED) and the ICICI vector (reused,
unchanged) proves the neutral outcome — no new fixture file needed for it. The `#[serde(default)]`
extension is the same period_start-stable pattern HDFC introduced, so a fixture that omits the keys
deserializes to `None`. Mismatch and the fallback are covered by `reconcile.rs` unit tests (constructed
statements), matching the web engine's split between integration fixtures and unit tests.

**Alternatives**: A dedicated mismatch/no-totals fixture file — rejected: the mismatch is a constructed
unit-test case in the web engine too, and the neutral case is already representable by the existing ICICI
vector; adding files would be redundant.

---

## D14 — Swift bridge test: `reconcileStatement`, `ReconcileStatus?`, three verdicts; swift-format spacing

**Decision**: New `ios/Tests/ReconcileTests.swift` (Swift Testing, `import KanameCore`) exercising
`reconcileStatement(statement:)` over the UniFFI bridge:
- read a Yes statement (extended `full_text`) via `readYesStatement`, then `reconcileStatement` →
  `result.status == .reconciled` and the printed totals surfaced (`printedDebits`/`printedCredits`);
- an IOB statement (via `readIobStatement`) → `.reconciled`;
- an ICICI statement (via `readIciciStatement`, no totals) → `result.status == nil` (neutral).

`status` surfaces in Swift as `ReconcileStatus?` (`nil` = neutral; `.reconciled` / `.needsReview` the
two variants). **swift-format `[Spacing]` forbids trailing inline `//` comments after code** — any
comment goes on its own line **above** the code. Requires `make core-xcframework` **before**
`tuist generate` (the generated `reconcileStatement` + `ReconcileResult`/`ReconcileStatus` Swift types
are build artifacts).

**Rationale**: FR-019/US8/SC-015 require the verdict reachable across the bridge, "exactly as it already
can call the balance-chain check". The existing `ICICIBankParseTests.swift` `balanceChainReconciles`
test is the precedent for calling a check over the bridge; this mirrors it for reconcile, distinguishing
RECONCILED / neutral (and the enum's `.needsReview` is exercised by the Rust side). The swift-format
spacing rule is a known gate constraint (the reader tests keep comments on their own line).

**Alternatives**: Asserting only one verdict — rejected: SC-015 requires the Swift test to **distinguish**
RECONCILED, NEEDS_REVIEW, and neutral; surfacing `.reconciled` and `nil` (plus the Rust-side
NEEDS_REVIEW coverage) satisfies the "distinguishable" requirement over the bridge.

---

## Verification harness (evidence)

A throwaway integration test (`core/crates/kaname-core/tests/tmp_reconcile_verify.rs`) using the **real**
`regex` + `rust_decimal` crates exercised the three **new** regexes over the exact fixture `full_text`
on the pinned stable toolchain, and **all passed**:

- **Yes `DEBITS_RE` / `CREDITS_RE`** (D10): on the extended Yes `full_text` →
  `debits = Some(100.00)`, `credits = Some(9000.00)` (the `9,000.00` thousands separator stripped by
  `parse_amount`).
- **IOB `SUMMARY_RE`** (D11): on the existing IOB `full_text` → `prev = "345.50"`,
  `credits = Some(1000.00)`, `debits = Some(3500.00)`, `fees = "0"`, `total = "2,845.50"`.
- **Read sums + tolerance** (D4/D5): `Decimal::new(100, 2) == Decimal::from_str("1.00")`; the
  ground-truth Yes/IOB read sums are within `1.00` of their printed totals (diff `0.00`).

The current core suite is green on the pinned toolchain (**63 unit tests + 13 parity/integration tests
pass**), so the reused types/harness/bridge are a stable foundation. The throwaway test was **removed
after verification** (nothing committed; `git status` clean apart from the plan artifacts). The full
`reconcile` behaviour (three tiers, tolerance boundary, precedence, retention) is proven end-to-end by
the `reconcile.rs` unit tests + the three reconcile parity cases in `/speckit.implement` (test-first).

---

## Resolved unknowns (summary)

| Unknown | Resolution |
|---|---|
| Module layout | `statement/reconcile.rs` beside `balance_chain.rs`; status enum + typed result record + one `pub fn` (D1). |
| Three-way outcome typing | `status: Option<ReconcileStatus>` with a **two-variant** enum; `None` = neutral, ≠ `Some(NeedsReview)` — 1:1 with the web `str \| None` (D2, FR-004). |
| Audit-detail shape | Typed `ReconcileResult` record mirroring the web `detail` dict (like `ChainResult`), not a dynamic dict (D3, FR-010). |
| Tolerance | `Decimal::new(100, 2)` (= 1.00), inclusive `<=`; the same constant `balance_chain` uses — **verified** (D4). |
| Read sums | `Σ line.amount` by `line.direction` over **all** rows; empty ⇒ 0.00; direction never from amount sign (D5, FR-002). |
| Primary tier | any printed total present ⇒ per-side `(read − printed).abs() <= tol`; all present pass ⇒ Reconciled else NeedsReview; fallback skipped (D6, FR-005/006/007). |
| Fallback tier | both balances present ⇒ `(computed − expected).abs() <= tol`, `expected = closing − opening`, `computed = debits − credits` (D7, FR-008). |
| Neutral tier | else ⇒ `status None`, `reason Some("no printed totals extracted")`; read sums still set (D8, FR-004/009). |
| New model fields | `printed_total_debits` / `printed_total_credits: Option<Decimal>`, default `None`; **`printed_total_spend` NOT added** (D9, FR-011). |
| Yes printed totals | `DEBITS_RE` / `CREDITS_RE` in `enrich`; same-line guard; **verified** `100.00` / `9000.00` (D10, FR-012). |
| IOB printed totals | `SUMMARY_RE` (`(?is)`) in `enrich`; credits = 2nd figure, debits = 3rd; **verified** `1000.00` / `3500.00` (D11, FR-013). |
| Bridge export | `reconcile_statement(statement) -> ReconcileResult`, mirroring `check_balance_chain`; `lib.rs` re-exports the fn + the two types (D12, FR-019). |
| Fixtures / parity | extend Yes/IOB `expected` (+ Yes `full_text`); reuse ICICI as the neutral vector; `Expected` gains `#[serde(default)]` printed totals + 3 reconcile parity tests (D13, FR-024). |
| Swift bridge test | `ReconcileTests.swift`: `.reconciled` (Yes/IOB) + `nil` neutral (ICICI); `ReconcileStatus?`; comments on their own line (D14, SC-015). |
| New dependency / new shared helper | **None** — pure drop-in reusing the shared statement types, `Decimal`, harness, bridge, privacy gate (D1, plan Constitution Check). |
