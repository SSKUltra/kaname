# Contract: Statement Reconciliation (`reconcile::reconcile`) — internal Rust seam

**Feature**: `012-cc-reconciliation` | **Date**: 2026-07-19
**Module**: `kaname-core::statement::reconcile`

The **credit-card counterpart** to `balance_chain::check` — a pure, per-statement integrity verification
over a parsed `ParsedStatement`. Ported 1:1 (behaviour) from the web engine's `reconciliation.py`. This
is a **stable behaviour contract**: given a `ParsedStatement`, `reconcile` returns exactly one of three
outcomes (RECONCILED / NEEDS_REVIEW / neutral) plus a typed audit `ReconcileResult`, with a fixed
three-tier decision ladder and an inclusive ₹1.00 tolerance. No new dependency, no new shared helper.

---

## `reconcile::reconcile` — the integrity check

```rust
pub fn reconcile(statement: &ParsedStatement) -> ReconcileResult
```

**Read sums (ALWAYS computed first, both tiers and neutral)**
- `read_debits = Σ line.amount where line.direction == Direction::Debit`.
- `read_credits = Σ line.amount where line.direction == Direction::Credit`.
- Direction comes from each row's own `Dr`/`Cr` marker — **never** re-derived from the amount's sign
  (FR-002). Empty `statement.lines` ⇒ both sums fold to `0.00` (never panics). Exact `Decimal`
  throughout — never `f64` (FR-017).
- `read_debits`/`read_credits` are set on the result in **every** outcome (FR-002, SC-012).

**Tolerance**
- `let tolerance = Decimal::new(100, 2);` — the constant `1.00`, the **same** value and the **same
  inclusive `<=`** comparison `balance_chain` uses. Exactly `1.00` is **within** tolerance (D4, SC-004).

**Three-tier ladder** (evaluated top-down; first applicable tier wins — FR-005..FR-009)

1. **Primary — printed totals present**
   `if statement.printed_total_debits.is_some() || statement.printed_total_credits.is_some()`:
   - For **each present** printed total, pass iff `(read − printed).abs() <= tolerance`
     (debit side vs `read_debits`, credit side vs `read_credits`).
   - `status = Some(Reconciled)` **iff every present** total passes, else `Some(NeedsReview)`.
   - Set `printed_debits`/`printed_credits` from the statement's fields (each `None` if that side was
     absent). Leave `expected_balance_change`/`computed_balance_change`/`reason` = `None`.
   - A missing side is simply **not checked** (only-one-total-present ⇒ verdict rests on that one side).

2. **Fallback — balance anchors present**
   `else if statement.printed_opening_balance.is_some() && statement.printed_closing_balance.is_some()`:
   - `expected = closing − opening`; `computed = read_debits − read_credits`.
   - `status = Some(Reconciled)` iff `(computed − expected).abs() <= tolerance`, else `Some(NeedsReview)`.
   - Set `expected_balance_change`/`computed_balance_change`. Leave printed_*/`reason` = `None`.
   - Requires **both** balances; one-or-neither ⇒ falls through to neutral (FR-009).

3. **Neutral — nothing to check**
   `else`: `status = None`, `reason = Some("no printed totals extracted".to_string())`. All
   printed_*/expected_*/computed_* remain `None`. `read_debits`/`read_credits` still set.

**Precedence invariant**: if **any** printed total is present, the primary tier runs and the fallback is
**never** consulted — even when both balance anchors are also present (FR-005, SC-008). This mirrors the
web engine's `if printed_debits is not None or printed_credits is not None:` leading branch.

**Neutral-vs-NeedsReview invariant**: the neutral outcome is `status == None`, **distinct** from
`Some(NeedsReview)`. A statement that simply lacks printed anchors is **not** flagged as a discrepancy
(FR-004, US3, SC-006). Only a present-but-disagreeing total/balance yields `NeedsReview`.

**Purity / totality**
- No I/O, no network, no clock, no locale, no global-state mutation; `statement` is borrowed `&` and
  never mutated. Identical input ⇒ identical output (FR-018, SC-013). Total — never panics, never
  surfaces an error (the three outcomes are the whole codomain).
- Rows are **never** dropped, mutated, or reordered by the check (FR-003, US5, SC-009); it only reads
  `amount` + `direction`.

---

## Truth table (the whole decision surface)

| Printed debits | Printed credits | Opening | Closing | Tier | `status` | Detail set |
|:-:|:-:|:-:|:-:|---|---|---|
| ✓ (\|Δ\|≤1) | ✓ (\|Δ\|≤1) | – | – | primary | `Some(Reconciled)` | printed_debits, printed_credits |
| ✓ (\|Δ\|>1) | ✓ | – | – | primary | `Some(NeedsReview)` | printed_debits, printed_credits |
| ✓ (\|Δ\|≤1) | – | – | – | primary | `Some(Reconciled)` | printed_debits (credits `None`) |
| – | ✓ (\|Δ\|>1) | – | – | primary | `Some(NeedsReview)` | printed_credits (debits `None`) |
| ✓ | – | (any) | (any) | primary | (per debit side) | printed_debits — **fallback skipped** |
| – | – | ✓ | ✓ (\|comp−exp\|≤1) | fallback | `Some(Reconciled)` | expected_/computed_balance_change |
| – | – | ✓ | ✓ (\|comp−exp\|>1) | fallback | `Some(NeedsReview)` | expected_/computed_balance_change |
| – | – | ✓ | – | neutral | `None` | reason |
| – | – | – | – | neutral | `None` | reason |

(`read_debits`/`read_credits` are set in **every** row above.)

---

## Golden behaviour (verified against the live web engine — the parity target)

| Vector | `read_debits` | `read_credits` | Printed | Outcome |
|---|--:|--:|---|---|
| **Yes** (extended fixture) | `100.00` | `9000.00` | debits `100.00`, credits `9000.00` | **RECONCILED** — detail `{readDebits 100.00, readCredits 9000.00, printedDebits 100.00, printedCredits 9000.00}` |
| **IOB** (existing fixture) | `3500.00` | `1000.00` | debits `3500.00`, credits `1000.00` | **RECONCILED** |
| **ICICI / HDFC / SBI / Federal** (no totals) | (row sums) | (row sums) | none | **neutral** — `status None`, `reason "no printed totals extracted"` |
| **Mismatch** (printed debit `9999`) | `100.00` | `9000.00` | debits `9999`, … | **NEEDS_REVIEW** — detail carries read + printed debit/credit |

---

## Unit tests (`reconcile.rs`) — mirroring `test_reconciliation.py` + the spec edge cases

`totals-match → Reconciled`; `debit-mismatch → NeedsReview` (+ detail read/printed);
`0.50-within-tolerance → Reconciled`; `exactly-1.00-boundary → Reconciled`; `only-one-total-present`;
`both-present-one-mismatch → NeedsReview`; `balance-change fallback → Reconciled`;
`primary-takes-precedence-over-fallback`; `only-one-balance → neutral`; `no-totals → neutral (None) with
reason`; `empty-rows sums 0.00`. Each asserts `status` **and** the relevant typed detail fields, and
compares money via `Decimal` value-equality (never float).

---

## Relationship to `balance_chain::check` (the reuse contract)

| | `balance_chain::check` | `reconcile::reconcile` |
|---|---|---|
| Input | `&ParsedStatement` | `&ParsedStatement` |
| Family | bank-account (balance-ledger) | credit-card (line) |
| Verdict enum | `ChainStatus { Reconciled, NeedsReview }` | `ReconcileStatus { Reconciled, NeedsReview }` |
| Neutral outcome | (n/a — always Reconciled/NeedsReview) | **`status: None`** (extra, distinct outcome) |
| Result record | `ChainResult` (typed detail) | `ReconcileResult` (typed detail) |
| Tolerance | `Decimal::new(100, 2)`, inclusive | **same** `Decimal::new(100, 2)`, inclusive |
| Money | exact `Decimal` | exact `Decimal` |
| Purity | pure/deterministic/total | pure/deterministic/total |
| FFI | `check_balance_chain` | `reconcile_statement` |

`reconcile.rs` is a **new sibling module** to `balance_chain.rs`; **no change** to `balance_chain.rs` is
made or expected. The two checks are independent — a statement is fed to whichever check matches its
family (bank-ledger → chain; credit-card → reconcile).
