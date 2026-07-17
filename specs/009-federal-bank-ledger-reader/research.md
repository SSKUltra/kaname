# Phase 0 — Research & Locked Decisions: Federal Bank Ledger Reader

**Feature**: 009-federal-bank-ledger-reader · **Date**: 2026-07-17
**Source of truth**: web engine `federal_bank.py` + captured JSON ground truth (`classic_savings`, `fi_neobank`, both RECONCILED).

Because this is a faithful port with a captured ground truth, the Technical Context had **no** `NEEDS CLARIFICATION`. Phase 0 therefore (a) records the **locked** design decisions and (b) **de-risks** the Rust-semantics parity questions with empirical evidence compiled against the crate's own dependency versions (**chrono 0.4.45, rust_decimal 1.42.1, regex 1**).

---

## Decision 1 — New reader `statement/federal_bank.rs`, a zero-sized `FederalBankReader` mirroring `hdfc_bank.rs`

- **Decision**: Add `FederalBankReader` implementing `LedgerReaderConfig`, structurally identical to `HdfcBankReader`. `anchor_res()` returns **two** patterns in order `[classic, fi]` (first-match-wins). `BANK_CODE = "FEDERAL"`; `claim_all = ["Federal Bank", "Statement of Account"]`; **no** `claim_any`; `opening_balance_re = Some(OPENING_RE)`; **no** `closing_balance_re`; **no** `column_split_x`; `account_tail(text) = account_tail_last4(text, &FEDERAL_ACCOUNT_RE)`; `enrich()` sets `period_start/period_end` from `PERIOD_RE` and `card_last4` from `account_tail`.
- **Rationale**: The base already provides every behaviour Federal needs. `hdfc_bank.rs` proves the exact shape (two anchors, opening regex, `account_tail_last4`, `enrich`). Federal differs only in its regexes/markers.
- **Locked patterns** (ported 1:1 from `federal_bank.py`, `(?i)` = the Python `re.IGNORECASE`):
  - **CLASSIC**: `(?i)^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+\d{2}-[A-Za-z]{3}-\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`
  - **FI**: `(?i)^(?P<date>\d{2}/\d{2}/\d{4})\s+\d{2}/\d{2}/\d{4}\s+(?P<desc>.*?)(?:\s+(?P<serial>S\d+))?\s+(?P<withdrawal>[\d,]+(?:\.\d{2})?)\s+(?P<deposit>[\d,]+(?:\.\d{2})?)\s+(?P<balance>[\d,]+\.\d{2})\s+(?:Cr|Dr)\s*$`
  - **OPENING**: `(?i)Opening Balance\s+(?:[A-Z]+\s+)?([\d,]+\.\d{2})`
  - **PERIOD**: `(?i)for the period(?:\s+of)?\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+to\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})`
  - **FEDERAL_ACCOUNT_RE**: `(?i)Account\s+Number\s*:?\s*X*([0-9]{4,})`
- **Alternatives considered**: (a) A single mega-regex for both templates — rejected: the base is designed for an ordered anchor **list**, and two clear patterns are more legible and exactly match the port. (b) Capturing the trailing `Cr`/`Dr` into a named group and using it for direction — **rejected and explicitly forbidden** (see Decision 3). (c) Adding a Federal-specific helper — rejected: `account_tail_last4` already does the job (Decision 6).

## Decision 2 — FFI surface `read_federal_bank_statement` + `federal_bank_claims` (parallel to the Scapia CC fns)

- **Decision**: In `ffi.rs` add `read_federal_bank_statement(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) -> ParsedStatement` wrapping `read_ledger_lines(&FederalBankReader, …)`, and `federal_bank_claims(full_text: String) -> bool` wrapping `claims_ledger(&FederalBankReader, …, "FEDERAL")`. Re-export both from `lib.rs`. Reuse `check_balance_chain` unchanged.
- **Rationale**: Exactly mirrors `read_icici_bank_statement`/`icici_bank_claims` and `read_hdfc_bank_statement`/`hdfc_bank_claims`. The names deliberately parallel the landed Scapia CC fns `read_federal_statement`/`federal_claims` — they **coexist** (see Decision 5).
- **Alternatives considered**: Overloading the existing `read_federal_statement` to sniff account kind — rejected: the ICICI/HDFC precedent is a **distinct** bank surface, and the caller (or a future registry) selects by account kind.

## Decision 3 — Trailing `Cr`/`Dr` is consumed but ignored; direction is delta-derived — VERIFIED

- **Decision**: The anchor matches `\s+(?:Cr|Dr)\s*$` as a **non-capturing** group with **no name**. The base's `find_anchors` only reads the named groups (`date`, `amount`/`withdrawal`/`deposit`, `balance`, `desc`, `serial`), so the marker plays **no** role. Direction comes from the balance delta (`balance < prev ⇒ Debit`, else `Credit`); row 1 is anchored on the printed opening balance.
- **Evidence** (parity of the classic fixture, where **every** printed marker is `Cr`): row 1 `100000.00→95000.00` ⇒ **Debit**; row 2 `95000.00→145000.00` ⇒ **Credit**; row 3 `145000.00→100000.00` ⇒ **Debit** — a debit/credit/debit mix despite three `Cr` markers. This is the defining Federal invariant (FR-007/008, SC-004) and the answer to the user's **"consumed-but-ignored"** sanity check: **confirmed** — the marker is matched and discarded, never read.

## Decision 4 — Whole-number Fi amounts reconcile against the 2-dp delta — VERIFIED

- **Decision**: The Fi withdrawal/deposit tokens are `[\d,]+(?:\.\d{2})?` (optional decimals). The base's `anchor_amount` picks the **non-zero** column and `loose_amount` parses it via `Decimal::from_str_exact`, preserving the printed scale (0 for `5000`). The amount-vs-delta check is `amount == delta.abs()`.
- **Evidence** (compiled against rust_decimal 1.42.1) — answers the user's **whole-number equality** sanity check:

  | Expression | Result |
  |---|---|
  | `from_str_exact("5000") == (dec(95000.00) - dec(100000.00)).abs()` | **`true`** |
  | `from_str_exact("50000") == (dec(145000.00) - dec(95000.00)).abs()` | **`true`** |
  | `from_str_exact("5000").to_string()` | `"5000"` (printed form preserved) |
  | `from_str_exact("50000").to_string()` | `"50000"` |
  | classic `from_str("5000.00").to_string()` | `"5000.00"` |

- **Conclusion**: rust_decimal compares by numeric value across scales, so `5000 == 5000.00`. Both Fi rows have `amount_matches_delta = true`, `is_suspect = false`. The fixture stores the amount strings **exactly** as `"5000"`/`"50000"` (classic as `"5000.00"` etc.), which the FFI/`to_string` round-trip preserves. **Confirmed.**

## Decision 5 — Shared `BANK_CODE = "FEDERAL"` does NOT clash with the landed Scapia reader — VERIFIED

- **Decision**: The bank reader coexists with the landed Scapia credit-card reader under the same issuer code, separated by `claims` gates and account kind — the deliberate ICICI/HDFC precedent (one issuer code, two account kinds).
- **No-clash analysis** (answers the user's **coexistence** sanity check):

  | Axis | Scapia CC (landed) | Federal bank (new) | Clash? |
  |---|---|---|---|
  | Module | `statement/federal.rs` | `statement/federal_bank.rs` | No — separate files |
  | Struct | `FederalReader` | `FederalBankReader` | No — distinct types |
  | Trait | `LineReaderConfig` | `LedgerReaderConfig` | No — different traits |
  | `BANK_CODE` const | `federal::BANK_CODE` | `federal_bank::BANK_CODE` | No — module-scoped; never referenced together |
  | FFI parse fn | `read_federal_statement` | `read_federal_bank_statement` | No — distinct exports |
  | FFI claims fn | `federal_claims` | `federal_bank_claims` | No — distinct exports |
  | Claim gate | requires `Scapia` | requires `Federal Bank` **and** `Statement of Account` | No — a Scapia CC statement lacks `Statement of Account` ⇒ bank reader rejects it; the CC reader still claims it |
- **Precedent**: identical to `icici.rs`/`icici_bank.rs` (both `"ICICI"`) and `hdfc.rs`/`hdfc_bank.rs` (both `"HDFC"`), already green in CI. **Confirmed — no module-level or FFI-level clash.**

## Decision 6 — Reuse `account_tail_last4` unchanged (no new shared helper)

- **Decision**: `account_tail(text)` calls the existing `common::account_tail_last4(text, &FEDERAL_ACCOUNT_RE)`, which tries the primary regex's group 1 (`tail4`), else the longest standalone `\d{9,}` run.
- **Evidence** (regex 1): `FEDERAL_ACCOUNT_RE` captures `99990100001234` (classic, full) → `tail4` `1234`; and `4222` from the masked `XXXXX4222` (Fi). Matches ground truth (`card_last4` `1234`/`4222`). Only the trailing four is ever surfaced (FR-021, privacy). **No new helper (SC-010).**

## Decision 7 — Fixtures: two golden vectors under `fixtures/federal/bank_account/`

- **Decision**: `classic.json` (3 rows) and `fi.json` (2 rows), each `{ lines, full_text, expected }`, following the `hdfc/bank_account/*.json` schema. The pre-existing `fixtures/federal/credit_card/basic.json` (Scapia) is **not** touched.
- **Critical serialization translation** (from the raw ground-truth JSON to the Kaname fixture — the parity harness compares `format!("{:?}", direction_source)` and serde-deserializes `Direction`):
  - `direction`: `"DEBIT"/"CREDIT"` → **`"Debit"/"Credit"`**
  - `direction_source`: `"opening_balance"/"balance_delta"` → **`"OpeningBalance"/"BalanceDelta"`**
  - row shape: `{value_date, amount, direction, description_raw, metadata:{…}}` → `{date, amount, direction, currency:"INR", description_raw, ledger:{balance, balance_delta, amount_matches_delta, is_suspect, direction_source, serial}}`
  - top level adds `printed_opening_balance`, `printed_closing_balance`, `period_start/end`, `card_last4`, `errored_lines: []`; the `balance_chain` block is **not** stored in the fixture (asserted by the separate chain test).
- **Rationale**: verified directly against the landed `hdfc/bank_account/compact.json`, whose `direction_source` is `"OpeningBalance"`/`"BalanceDelta"` and `direction` is `"Debit"`/`"Credit"`.

## Decision 8 — Narration stitching reproduces the web-engine quirks byte-for-byte — TRACED

Hand-trace of the **unchanged** base `stitch_narration` (Part A = line directly above the anchor; Part B = lines below up to *but excluding* the line directly above the next anchor; skip anchors and `is_balance_line`):

**Classic** (anchors at line indices 6, 8, 10; opening line 5 is a balance line):
- Row 1 (idx 6): A=[5]→skipped (balance); B=`(7..7)`=∅ ⇒ `"TO ECM/600000000001 TFR"` ✅
- Row 2 (idx 8): A=[7]=`/EXAMPLEMERCHANT \EXAM/07:17`; B=`(9..9)`=∅ ⇒ `"UPI IN/600000000002 TFR /EXAMPLEMERCHANT \EXAM/07:17"` ✅ (row 1's continuation folds into row 2)
- Row 3 (idx 10): A=[9]=`/payer@example/Payment/0000`; B=`(11..13)`=[11,12]=`\EXAM/12:34`,`GRAND TOTAL 50,000.00 50,000.00` ⇒ `"POS/600000000003/EXAMPLESTORE TFR /payer@example/Payment/0000 \EXAM/12:34 GRAND TOTAL 50,000.00 50,000.00"` ✅ (own continuation + `GRAND TOTAL` fold into the last row)

**Fi** (anchors at indices 5, 7; opening line 4 is a balance line):
- Row 1 (idx 5): A=[4]→skipped; B=`(6..6)`=∅ ⇒ `"TO ECM/600000000001/EXAMPLE TFR"` ✅
- Row 2 (idx 7): A=[6]=`MERCHANT \EXAM`; B=`(8..9)`=[8]=`Payment f/0000` ⇒ `"UPI IN/600000000002/payer TFR MERCHANT \EXAM Payment f/0000"` ✅

**`GRAND TOTAL` never becomes a transaction** (regex 1, verified): `"GRAND TOTAL 50,000.00 50,000.00"` matches neither anchor (no leading date, no trailing `Cr`/`Dr`). It is folded into row 3 only as narration. Matches ground truth exactly (FR-016/017, SC-007). **No base change; the quirks are reproduced, not fixed.**

## Decision 9 — Anchor group-splitting (`serial` out of `desc`, non-zero column) — VERIFIED

Empirical `regex 1` captures on the exact fixture lines:

| Line | `desc` | `serial` | amount/columns | `balance` |
|---|---|---|---|---|
| classic row 1 | `TO ECM/600000000001 TFR` | `S10000001` | `amount=5,000.00` | `95,000.00` |
| fi row 1 | `TO ECM/600000000001/EXAMPLE TFR` | `S10000001` | `w=5000 d=0` → 5000 | `95,000.00` |
| fi row 2 | `UPI IN/600000000002/payer TFR` | `S10000002` | `w=0 d=50000` → 50000 | `1,45,000.00` |

The non-greedy `desc` + greedy optional `(?:\s+(?P<serial>S\d+))?` yields the shortest `desc` that still lets the tail parse, so the `S…` id is captured as `serial` and kept **out** of `desc` (FR-012/013, SC-006). **Confirmed.** Opening regex reads `1,00,000.00` from both `Opening Balance 1,00,000.00 Cr` and `Opening Balance OPNBAL 1,00,000.00 CR` (the `OPNBAL` tolerated by `(?:[A-Z]+\s+)?`).

## Decision 10 — Dates need no new format

- **Decision**: reuse `DATE_FORMATS`. Classic `08-APR-2026` → `%d-%b-%Y`; Fi `08/04/2026` → `%d/%m/%Y` (with `%d/%m/%y` correctly ordered first); ISO period `2026-04-01` → `%Y-%m-%d`.
- **Evidence** (chrono 0.4.45) — answers the uppercase-month risk: `parse_date("08-APR-2026")` = `Some(2026-04-08)`, `parse_date("13-APR-2026")` = `Some(2026-04-13)`, `parse_date("07/05/2026")` = `Some(2026-05-07)`. chrono matches `%b` case-insensitively, so uppercase `APR` parses. **No new date format (FR-026, SC-010).**

---

## Open questions

**None.** All ported decisions are locked, all three user-flagged Rust-semantics questions are empirically resolved (Decisions 3, 4, 5), and the ground truth is captured. Ready for Phase 1 / `/speckit.tasks`.
