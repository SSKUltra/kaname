# Phase 0 — Research & Locked Decisions: AU Small Finance Bank Ledger Reader

**Feature**: 010-au-bank-ledger-reader · **Date**: 2026-07-17
**Source of truth**: web engine `au_bank.py` + captured JSON ground truth (`savings`, RECONCILED).

This is a faithful **config-on-an-existing-base** port with a captured ground truth, so the Technical Context had **no** `NEEDS CLARIFICATION`. Phase 0 therefore (a) records the **locked** design decisions and (b) **de-risks** the two user-flagged parity questions — the **dash-marked empty column** and the **printed-closing-balance source** — with empirical evidence compiled against the crate's own dependency versions (**regex 1.12.4, rust_decimal 1.42.1, chrono 0.4.45**, from `core/Cargo.lock`).

> **Empirical method**: a throwaway binary pinned to the exact three crate versions replicated the base's `anchor_amount`/`loose_amount` and ran the locked AU regexes over the ground-truth `lines`. All assertions below passed (`ALL ASSERTIONS PASSED`). The scratch project was discarded (no repo changes).

---

## Decision 1 — New reader `statement/au_bank.rs`, a zero-sized `AuBankReader` mirroring `federal_bank.rs`/`icici_bank.rs`, with ONE anchor

- **Decision**: Add `AuBankReader` implementing `LedgerReaderConfig`, structurally identical to `IciciBankReader` (which also uses `claim_any` + `closing_balance_re`), but with **one** anchor pattern. `anchor_res()` returns `vec![&ANCHOR_RE]`. `BANK_CODE = "AU"`; `claim_all = ["aubank.in"]`; `claim_any = ["Savings Account", "Current Account"]`; `opening_balance_re = Some(OPENING_RE)`; `closing_balance_re = Some(CLOSING_RE)`; **no** `column_split_x`; `account_tail(text) = account_tail_last4(text, &AU_ACCOUNT_RE)`; `enrich()` sets `period_start/period_end` from `PERIOD_RE` (via `parse_date`) and `card_last4` from `account_tail`.
- **Rationale**: The base already provides every behaviour AU needs — a two-column `withdrawal`/`deposit` pair with the empty side skipped (proven by the Fi/HDFC `0`-empty layout), opening-balance extraction, `is_balance_line` narration-skip using `opening_balance_re`/`closing_balance_re`, the row-1 opening bootstrap, and the errored-vs-suspect distinction. AU differs only in its regexes/markers. This is the **leanest** ledger drop-in of the family: a **single** template.
- **Locked patterns** (ported 1:1 from `au_bank.py`):
  - **ANCHOR** (no `(?i)` — dates are `[A-Za-z]{3}`, matching the ICICI anchor style):
    `^(?P<date>\d{2} [A-Za-z]{3} \d{4})\s+\d{2} [A-Za-z]{3} \d{4}\s+(?P<desc>.*?)\s*(?P<withdrawal>[\d,]+\.\d{2}|-)\s+(?P<deposit>[\d,]+\.\d{2}|-)\s+(?P<balance>[\d,]+\.\d{2})\s*$`
  - **OPENING**: `(?i)Opening Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})`
  - **CLOSING**: `(?i)Closing Balance\s*\([^)]*\)\s*:\s*([\d,]+\.\d{2})`
  - **PERIOD**: `(?i)Statement Period\s*:\s*(\d{2} [A-Za-z]{3} \d{4})\s+to\s+(\d{2} [A-Za-z]{3} \d{4})`
  - **AU_ACCOUNT_RE**: `(?i)Account\s+Number\s*:?\s*X*([0-9]{6,})`
- **Alternatives considered**: (a) A dedicated dash-handling code path in the base — **rejected**: unnecessary, the base's `loose_amount` already returns `None` for `-` (Decision 3). (b) A Federal-style single-`amount` anchor — rejected: AU prints **two** columns (Debit + Credit), so the `withdrawal`/`deposit` pair is the faithful shape. (c) A new shared helper for the account tail — rejected: `account_tail_last4` already does the job.

## Decision 2 — FFI surface `read_au_bank_statement` + `au_bank_claims` (parallel to the ICICI/HDFC/Federal bank fns)

- **Decision**: In `ffi.rs` add `read_au_bank_statement(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) -> ParsedStatement` wrapping `read_ledger_lines(&AuBankReader, …)`, and `au_bank_claims(full_text: String) -> bool` wrapping `claims_ledger(&AuBankReader, …, "AU")`. Re-export both from `lib.rs`. Reuse `check_balance_chain` unchanged.
- **Rationale**: Exactly mirrors `read_federal_bank_statement`/`federal_bank_claims` (and the ICICI/HDFC pairs). `first_row_words` is accepted for signature parity but **unused** by AU (no `column_split_x`; the fixture is opening-anchored) — the harness/app pass an empty `Vec`.
- **Alternatives considered**: A registry-based dispatch — out of scope for this slice; the explicit per-issuer fn mirrors the three landed bank readers.

## Decision 3 — Dash-marked empty column resolves via the base's existing `loose_amount` → `None` — VERIFIED

- **Decision**: The anchor captures `withdrawal`/`deposit` where each side is **either** a money token **or** a literal `-`. The base's `anchor_amount` calls `loose_amount` on each; `loose_amount("-")` returns `None` (because `Decimal::from_str_exact("-")` errors), so the non-dash side becomes the amount. **No base change.**
- **Evidence** (compiled against regex 1.12.4 + rust_decimal 1.42.1) — the direct answer to the user's **dash-empty** sanity check:

  | Input | Result |
  |---|---|
  | `loose_amount("-")` | **`None`** |
  | `loose_amount("5,000.00")` | `Some(5000.00)` |
  | row 1 anchor `… 5,000.00 - 6,570.79` → `anchor_amount` | **`5000.00`** (Debit column; deposit `-` ignored) |
  | row 2 anchor `… - 10,000.00 16,570.79` → `anchor_amount` | **`10000.00`** (Credit column; withdrawal `-` ignored) |

- **Conclusion**: The dash is handled entirely by the **unchanged** base. This is exactly the Fi/HDFC `0`-empty mechanism, except the empty sentinel is `-` (which `loose_amount` maps to `None`) rather than `0` (which it maps to `Some(0)` and `anchor_amount` skips via `!is_zero()`). Either way the non-empty side wins. **Confirmed.**

## Decision 4 — Printed closing balance is the LAST anchor's running balance, NOT the header figure — VERIFIED

- **Decision**: `read_ledger_lines` sets `statement.printed_closing_balance = Some(anchors[anchors.len() - 1].balance)` unconditionally (`ledger_reader.rs:195`). AU's last anchor balance is **16570.79**, so that is the printed closing balance. The header line `Closing Balance(₹) : 223.34` is **only** matched by `closing_balance_re` inside `is_balance_line` to **skip** it during narration stitching (`ledger_reader.rs:395–400`); its figure is **never** assigned to `printed_closing_balance`.
- **Evidence** — the direct answer to the user's **printed-closing** sanity check:
  - Base source: `printed_closing_balance` is the last anchor balance (no code path reads `closing_balance_re` for the value).
  - Ground truth agrees: `printed_closing_balance = "16570.79"` (= last row balance), **not** `"223.34"` (the header figure).
- **Conclusion**: `printed_closing_balance = 16570.79` is the **intended parity value**; the `223.34` header figure is intentionally discarded. `closing_balance_re` exists purely so the `Closing Balance(₹)` line is recognized as a non-transaction and excluded from stitching. **Confirmed.**

## Decision 5 — Direction is delta-derived; the narration's `UPI/DR`/`UPI/CR` is counterparty text, never a signal — VERIFIED

- **Decision**: The anchor carries **no** direction marker (unlike Federal's consumed-but-ignored trailing `Cr`/`Dr`). Direction comes solely from the balance delta (`balance < prev ⇒ Debit`, else `Credit`); row 1 is anchored on the printed opening balance. The `UPI/DR`/`UPI/CR` tokens live **inside** `description_raw` and are read by nothing.
- **Evidence** (the ground truth's coincidence that must not drive direction): row 1 delta `6570.79 − 11570.79 = −5000.00 ⇒ **Debit**` (its narration contains `UPI/DR`); row 2 delta `16570.79 − 6570.79 = +10000.00 ⇒ **Credit**` (its narration contains `UPI/CR`). Directions follow the deltas, and would still be debit-then-credit if the `UPI/DR`/`UPI/CR` tokens were absent. `amount == |delta|` for both rows ⇒ `amount_matches_delta = true`, `is_suspect = false`. **Confirmed** (FR-006/007/008, SC-003).

## Decision 6 — AU is the SOLE reader under bank code `AU` (no coexisting credit-card reader)

- **Decision**: `BANK_CODE = "AU"` is introduced by this slice and used only by `AuBankReader`. Unlike ICICI/HDFC/Federal (each of which shares its issuer code with a landed credit-card reader), **AU has no credit-card reader in this client**.
- **Analysis** (answers the user's registry sanity check): the gate rejects a non-savings/current document by the `claim_any = ["Savings Account", "Current Account"]` requirement — a credit-card statement lacking that marker is declined; a wrong-`bank_code` caller is declined by `claims_ledger`'s first guard. No module/struct/trait/FFI-name clash exists because there is no second `AU` reader. **Confirmed — sole reader, clean gate.**

## Decision 7 — Reuse `account_tail_last4` unchanged (no new shared helper)

- **Decision**: `account_tail(text)` calls the existing `common::account_tail_last4(text, &AU_ACCOUNT_RE)`, which tries the primary regex's group 1 (`tail4`), else the longest standalone `\d{9,}` run.
- **Evidence** (regex 1.12.4): `AU_ACCOUNT_RE` captures `1234567890120042` → `tail4` = **`0042`** (matches the ground truth `card_last4`). Only the trailing four is ever surfaced (FR-020, privacy). **No new helper (SC-008).**

## Decision 8 — Narration stitching reproduces the web-engine quirks byte-for-byte — TRACED

Hand-trace of the **unchanged** base `stitch_narration` (Part A = the line directly above the anchor; Part B = lines below, up to *but excluding* the line directly above the next anchor; skip anchors and `is_balance_line`). Anchor line indices = **9, 12**. Balance lines (skipped if encountered): 3 (`Opening Balance(₹)…`) and 4 (`Closing Balance(₹)…`).

- **Row 1** (idx 9): A = `[8]` = `UPI/DR/000000000001/EXAMPLE ABC0000000001ref`; B = `(10 .. 11)` = `[10]` = `MERCHANT/UTIB/0000/UPI AU` ⇒
  `STORE 1111ref2222tail UPI/DR/000000000001/EXAMPLE ABC0000000001ref MERCHANT/UTIB/0000/UPI AU` ✅
- **Row 2** (idx 12): A = `[11]` = `UPI/CR/000000000002/EXAMPLE XYZ0000000002ref`; B = `(13 .. 15)` = `[13,14]` = `SALARY/UTIB/0000/UPI AU`, `1800 1200 1200 www.aubank.in customercare@aubank.in` ⇒
  `EMPLOYER 3333ref4444tail UPI/CR/000000000002/EXAMPLE XYZ0000000002ref SALARY/UTIB/0000/UPI AU 1800 1200 1200 www.aubank.in customercare@aubank.in` ✅

Both reproduce the ground truth exactly. Notes: (a) the `UPI/…` line **above** each anchor folds into **that** row (Part A); (b) the trailing **footer** line 14 folds into the **last** row (Part B, non-anchor, non-balance); (c) the header/column-header lines (0–7) are never candidates because Part A only takes the single line directly above the anchor and Part B starts below it — so the statement yields exactly **2** rows. The footer `1800 1200 1200 www.aubank.in customercare@aubank.in` does **not** match the anchor (no two leading `DD Mon YYYY` dates), verified empirically. **No base change; the quirks are reproduced, not fixed** (FR-015/016, SC-005).

## Decision 9 — Anchor group-splitting (`desc` vs dash columns) — VERIFIED

Empirical `regex 1.12.4` captures on the exact ground-truth lines:

| Line | `date` | `desc` | `withdrawal` | `deposit` | `balance` | `anchor_amount` |
|---|---|---|---|---|---|---|
| row 1 (idx 9) | `01 Mar 2026` | `STORE 1111ref2222tail` | `5,000.00` | `-` | `6,570.79` | `5000.00` |
| row 2 (idx 12) | `02 Mar 2026` | `EMPLOYER 3333ref4444tail` | `-` | `10,000.00` | `16,570.79` | `10000.00` |

The non-greedy `desc` stops at the first position where the `withdrawal … deposit … balance` tail parses; the digit-bearing `1111ref2222tail`/`3333ref4444tail` tokens carry no `.dd` money shape and no `-`, so they stay in `desc`. AU's anchor has **no** `serial` group ⇒ every row's `serial` is empty (FR-017). **Confirmed.**

## Decision 10 — Dates & document gate need no new format/helper

- **Dates**: reuse `DATE_FORMATS`. `01 Mar 2026` → `%d %b %Y` (already present, `common.rs:30`). Empirically `parse_date("01 Mar 2026") = 2026-03-01`, period `01 Mar 2026 → 31 May 2026`. **No new date format** (FR-025, SC-008).
- **Gate**: `claims_ledger` matches `claim_all` (all present, case-insensitive) then `claim_any` (any present). For AU: `aubank.in` **and** (`Savings Account` **or** `Current Account`). The ground truth's `Account Type : AU Lite Savings Account` satisfies `claim_any`. A document with `aubank.in` but no Savings/Current marker is declined (FR-001/002).

## Decision 11 — Fixture: one golden vector under `fixtures/au/bank_account/savings.json`

- **Decision**: `savings.json` (2 rows), shaped `{ lines, full_text, expected }`, following the `federal/bank_account/*.json` schema. It is the sole file under the new `fixtures/au/` subtree.
- **Critical serialization translation** (from the raw ground-truth JSON to the Kaname fixture — the parity harness serde-deserializes `direction` and compares `format!("{:?}", direction_source)`):
  - `direction`: `"DEBIT"/"CREDIT"` → **`"Debit"/"Credit"`**
  - `direction_source`: `"opening_balance"/"balance_delta"` → **`"OpeningBalance"/"BalanceDelta"`**
  - row shape: `{value_date, amount, direction, description_raw, metadata:{…}}` → `{date, amount, direction, currency:"INR", description_raw, ledger:{balance, balance_delta, amount_matches_delta, is_suspect, direction_source, serial}}`
  - top level adds `period_start/period_end`, `card_last4`, `printed_opening_balance`, `printed_closing_balance`, `errored_lines: []`; the `balance_chain` block is **not** stored in the fixture (asserted by the separate chain test).
- **Preserve the `₹` glyph**: the header lines contain `Opening Balance(₹)` / `Closing Balance(₹)` with a literal U+20B9 — kept verbatim in both `lines` and `full_text`. `lines` = the non-empty, stripped `splitlines()` of `full_text` (15 lines; anchors at indices 9 and 12).
- **Rationale**: verified against the landed `federal/bank_account/fi.json`, whose `direction_source` is `"OpeningBalance"`/`"BalanceDelta"` and `direction` is `"Debit"`/`"Credit"`.

---

## Open questions

**None.** All ported decisions are locked; both user-flagged questions are empirically resolved — the **dash-empty column** via the base's unchanged `loose_amount("-") → None` (Decision 3) and the **printed closing balance** as the last anchor balance `16570.79` (not the header `223.34`) (Decision 4). The ground truth is captured. Ready for Phase 1 / `/speckit.tasks`.
