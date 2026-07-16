# Phase 0 Research: HDFC Bank (Savings/Current) Ledger Reader — HDFC Config on the Existing Base (Two Layouts)

**Feature**: `008-hdfc-bank-ledger-reader` | **Date**: 2026-07-16 | **Plan**: [`plan.md`](./plan.md)

This slice is a **config-on-an-existing-base** port with a **locked** Rust design (supplied by the requester)
and a **persisted ground truth**, so "research" here is **verification**, not option-shopping. I confirmed
every locked decision against three independent sources and recorded the one genuine open item.

## Method / evidence base

Each decision below was checked against **all** of:

1. **The web-engine source** — `finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc_bank.py` (the authority for behaviour we port).
2. **The persisted ground truth** — `hdfc-bank-ground-truth.json` (both the compact and detailed reference vectors, with exact expected rows, ledger fields, serials, printed balances, period, account last-4).
3. **An out-of-repo Rust replica** — a scratch `cargo` project (**outside** the repo; commits nothing) pinned to kaname's resolved crate versions (`regex 1.13.1`, `chrono 0.4.45`, `rust_decimal 1.42.1`) that reimplements the base `read_ledger_lines` loop + the proposed `HdfcBankReader` config and asserts ~63 values against the ground truth for **both** fixtures. **Result: 63/63 green** once D8's `DATE_FORMATS` reorder is applied (without it, exactly the two compact **dates** fail — see D8).

The base itself (`ledger_reader.rs`, `balance_chain.rs`), the parity-harness schema, and the privacy-egress gate are **reused UNCHANGED** — they landed and were validated in slice 007. Constitution v1.0.0 (all 5 principles + the iOS gate) governs; this slice is squarely a **Principle V (test-first parity)** exercise.

---

## D1 — Shared `account_tail_last4(text, primary)` helper in `common.rs` (+ behaviour-preserving `icici_bank.rs` refactor)

**Decision.** Add the **only** new shared code: `pub fn account_tail_last4(text: &str, primary: &Regex) ->
Option<String>` in `common.rs` — try `primary` (**capture group 1**, take the **trailing 4** of the captured
digits); else the **longest standalone `\d{9,}` run** (via the existing `DIGIT_RUN_RE` logic, moved here),
trailing 4; else `None`. Refactor `icici_bank.rs` to call it with ICICI's own primary regex
`(?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})`, dropping its local `last4` / `DIGIT_RUN_RE` /
`account_tail`.

**Rationale.** The ≥9-digit "longest standalone run → last 4" fallback is **identical** across banks (it mirrors
Python's `(?<!\d)(\d{9,})(?!\d)` — Rust `regex` has no look-around, but greedy **non-overlapping** `\d{9,}`
already yields the maximal runs, so `max_by_key(len)` reproduces Python's "longest" pick). Only the **primary**
account pattern differs per issuer. A per-bank primary + shared fallback is the faithful port and directly
serves FR-018/FR-022 (later Federal/AU readers reuse it).

**Verification.**
- ICICI back-compat (**must stay GREEN**): `…Account Number: 000401000123456…` → group 1 `000401000123456`
  → **`3456`** (matches the landed `icici/bank_account/basic.json`). ✅
- HDFC (via its own `HDFC_ACCOUNT_RE`, D2): both fixtures' `…Account Number : 50100359253425…` →
  **`3425`**. ✅
- Fallback path exercised in isolation: longest `\d{9,}` run of a mixed text → trailing 4. ✅

**Alternatives rejected.** Duplicating the fallback per reader (drift; re-implements identical logic — the very
duplication the helper prevents). Making the helper take a `&[&Regex]` list (unneeded; one primary per bank
suffices today; keep the signature minimal).

---

## D2 — `HdfcBankReader` config with **two** ordered anchors (compact, detailed)

**Decision.** New `statement/hdfc_bank.rs`: a zero-sized `HdfcBankReader` implementing `LedgerReaderConfig`,
mirroring `icici_bank.rs`, returning **two** anchors from `anchor_res()` in order `[COMPACT, DETAILED]`:

- **COMPACT** `^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`
- **DETAILED** `^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$`

`BANK_CODE "HDFC"`. No `closing_balance_re`; no `column_split_x`.

**Rationale.** HDFC ships two export layouts; the base **already** tries an ordered anchor list first-match-wins
(`anchor_res() -> Vec<&'static Regex>`), and HDFC is simply the first config to supply more than one (FR-003/006).
COMPACT captures the alphanumeric reference as `serial` and has a single `amount`; DETAILED uses the
`withdrawal`/`deposit` **two-column** shape that `anchor_amount` already handles (the empty side is `0.00`; the
base picks the non-zero via `loose_amount` = comma-strip + `Decimal::from_str_exact`).

**Verification.**
- **Mutual exclusion:** a compact row (2-digit year) never matches DETAILED and vice-versa (4-digit year); the
  ordered list therefore yields the intended layout for each fixture with no cross-talk. ✅
- **COMPACT rows** → `serial` `0000600000000001` (row 1) and `CITIN26653417445` (row 2); single `amount`
  `5,000.00` / `50,000.00`; `balance` `95,000.00` / `1,45,000.00`. ✅
- **DETAILED rows** → `withdrawal`/`deposit` pair resolves to `5,000.00` (Debit) / `50,000.00` (Credit); empty
  `serial`. ✅
- Amounts/balances parse via `parse_amount` (`Decimal`), never `f64`. ✅

**Alternatives rejected.** Two separate readers (doubles claims/FFI/fixture surface for one issuer; hides the
layout choice the base already models). A single mega-anchor with optional groups (unreadable; the 2-vs-4-digit
year cleanly separates the two).

---

## D3 — `opening_balance_re` matches **both** layouts, including the compact summary row across a newline  ✅ (requester-flagged sanity item #1 — CONFIRMED)

**Decision.** `opening_balance_re` = `(?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})`
— capture **group 1** is the opening balance in **both** alternatives. No separate closing pattern.

**Why this is the right pattern (and the confirmation you asked for).** HDFC prints the opening balance two
different ways:
- **Detailed (inline):** `Opening Balance : 1,00,000.00` → **alt 1** (`Opening Balance\s*:\s*`) → group 1
  `1,00,000.00`.
- **Compact (end-of-statement summary, spanning a newline):**
  `… OpeningBalance DrCount CrCount Debits Credits ClosingBal\n1,00,000.00 1 1 …` → **alt 2**
  (`OpeningBalance\b[^\n]*\n\s*`) consumes the header label line up to and across the `\n`, then group 1 grabs
  the **first** `[\d,]+\.\d{2}` on the value line → `1,00,000.00`.

**Rust-specific confirmation.** Rust `regex` treats `.` as "not newline" and, crucially, **`\n` and `[^\n]`
work without any multi-line/`(?s)` flag** — the pattern is a plain single-string match over the whole
`full_text`, so the newline-spanning alt behaves exactly as intended. Verified: both fixtures →
`printed_opening_balance = "100000.00"` (the harness stores the normalized `Decimal` string). ✅
`printed_closing_balance = "145000.00"` is derived by the reader from the **final row's balance** (there is no
closing regex), matching the ground truth. ✅

---

## D4 — Narration stitching reproduces the web-engine quirks **byte-for-byte**  ✅ (requester-flagged sanity item #2 — CONFIRMED)

**Decision.** Reuse the base `stitch_narration` unchanged. Confirm that the reused per-line `is_balance_line`
predicate reproduces the web engine's *intentional* header/summary-into-narration stitching.

**What the base does (reused, unchanged).** For each anchored row the narration = inline `desc` + the line
immediately **above** + the lines **below** up to the next anchor, **skipping** any line that is itself an
anchor or that `is_balance_line` (i.e. matches `opening_balance_re`/`closing_balance_re`) treats as a
balance line. Critically, `is_balance_line` is evaluated **per single line** (no cross-line context).

**The confirmed quirks (these are correct parity, not bugs):**
- **Both layouts, row 0** stitches the **column-header line** into the first row's narration, because the header
  sits between the period/opening preamble and the first anchor and is neither an anchor nor a balance line:
  - Compact row-0 desc = `"UPI-EXAMPLEMERCHANT Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt.
    ClosingBalance"`. ✅
  - Detailed row-0 desc = `"UPI-EXAMPLEMERCHANT Txn Date Narration Withdrawals Deposits Closing Balance"`. ✅
- **Compact row 1** stitches the **trailing end-of-statement summary rows** into the last row's narration:
  `"NEFTCR-EXAMPLEEMPLOYER OpeningBalance DrCount CrCount Debits Credits ClosingBal 1,00,000.00 1 1 5,000.00
  50,000.00 1,45,000.00"`. **Why it's included (the subtle bit):** although alt 2 of `opening_balance_re` *can*
  match the `OpeningBalance…\n1,00,000.00` **pair** at the `full_text` level (that's how D3 finds the opening),
  `is_balance_line` runs against **isolated single lines** — and neither the lone `OpeningBalance Dr… ClosingBal`
  header line **nor** the lone `1,00,000.00 1 1 …` value line matches `opening_balance_re` on its own (the `\n`
  alt needs a newline it doesn't have in isolation, and the inline alt needs `Opening Balance :`). So both lines
  are (correctly, per the web engine) **not** treated as balance lines and get stitched in. ✅
- **Detailed row 1** desc = `"UPI-EXAMPLEEMPLOYER salary"` (a plain continuation; no summary block in the
  detailed layout). ✅

All four narrations reproduce **exactly** in the Rust replica. This confirms the header/summary lines are
**intentionally** part of the narration for parity — no post-processing/cleanup is added (doing so would break
parity vs the web engine).

---

## D5 — Enrichment: period + account last-4 (`account_tail_last4`)

**Decision.** `enrich` sets:
- **Period** via `PERIOD_RE` `(?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})` → `parse_date`
  on groups 1 & 2 → `period_start = 2026-04-01`, `period_end = 2026-04-30`. **Note the optional colon** after
  `To` (`:?`) — the ground-truth preamble is `From : 01/04/2026 To 30/04/2026` (no colon after `To`); the
  optional colon tolerates both. ✅ (Both dates are 4-digit `%d/%m/%Y`, unaffected by D8.)
- **Account last-4** via `card_last4 = account_tail_last4(full_text, HDFC_ACCOUNT_RE)` with `HDFC_ACCOUNT_RE`
  `(?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})` → group 1 `50100359253425` → **`3425`** (both
  fixtures). ✅

**Rationale / HDFC vs ICICI differences (faithful to `hdfc_bank.py`).** HDFC's account label uses `\s*`
(not ICICI's `\s+`), tolerates a **masked `X*` prefix**, and needs only **4+** digits (`[0-9]{4,}` vs ICICI's
`[0-9]{6,}`) — HDFC statements can show `XXXXXXXX3425`. The shared fallback (longest `\d{9,}` run) still applies
if the labelled form is absent. Confirmed the differing quantifiers/anchors don't change the ICICI result
(ICICI keeps its own regex; D1).

---

## D6 — Two golden fixtures under `fixtures/hdfc/bank_account/`

**Decision.** Author `compact.json` and `detailed.json` from the ground truth. Each fixture's `lines` = the
**non-empty, stripped `splitlines()`** of its `full_text` (the harness contract from 007), and `expected`
carries: `rows[]` (date, amount, direction `Debit`/`Credit`, currency `INR`, `description_raw`, and per-row
`ledger{ balance, balance_delta, amount_matches_delta, is_suspect, direction_source, serial }`),
`period_start/period_end`, `card_last4`, `printed_opening_balance`, `printed_closing_balance`, `errored_lines`.

**Exact expected values (both fixtures; verified end-to-end in the replica):**

| | **compact.json** | **detailed.json** |
|---|---|---|
| period | `2026-04-01` → `2026-04-30` | same |
| card_last4 | `3425` | `3425` |
| printed_opening / closing | `100000.00` / `145000.00` | same |
| errored_lines | `[]` | `[]` |
| **row 0** | `2026-04-01`, `5000.00`, **Debit**, desc = `UPI-EXAMPLEMERCHANT Date Narration Chq./Ref.No. ValueDt WithdrawalAmt. DepositAmt. ClosingBalance`, ledger{ balance `95000.00`, delta `-5000.00`, matches **true**, suspect **false**, **OpeningBalance**, serial `0000600000000001` } | `2026-04-01`, `5000.00`, **Debit**, desc = `UPI-EXAMPLEMERCHANT Txn Date Narration Withdrawals Deposits Closing Balance`, ledger{ balance `95000.00`, delta `-5000.00`, matches **true**, suspect **false**, **OpeningBalance**, serial `` (empty) } |
| **row 1** | `2026-04-16`, `50000.00`, **Credit**, desc = `NEFTCR-EXAMPLEEMPLOYER OpeningBalance DrCount CrCount Debits Credits ClosingBal 1,00,000.00 1 1 5,000.00 50,000.00 1,45,000.00`, ledger{ balance `145000.00`, delta `50000.00`, matches **true**, suspect **false**, **BalanceDelta**, serial `CITIN26653417445` } | `2026-04-20`, `50000.00`, **Credit**, desc = `UPI-EXAMPLEEMPLOYER salary`, ledger{ balance `145000.00`, delta `50000.00`, matches **true**, suspect **false**, **BalanceDelta**, serial `` (empty) } |

**Direction reasoning (delta-derived, not amount-derived).** Row 0 direction is set from the **opening
balance** anchor (`100000.00 → 95000.00` ⇒ Debit; `direction_source = OpeningBalance`); row 1 from the running
**balance delta** (`95000.00 → 145000.00` ⇒ +50000 ⇒ Credit; `direction_source = BalanceDelta`). The printed
amount is an **independent** cross-check: `amount_matches_delta = true` on every row (EXACT match in the reader;
the ₹1.00 tolerance lives only in `balance_chain`). All fixture money values are **strings** so `serde_json`
never routes a monetary amount through `f64` (Principle II). Data is **synthetic/redacted** (Principle V,
FR-032): fabricated `EXAMPLEMERCHANT`/`EXAMPLEEMPLOYER`, synthetic account `50100359253425`.

**`serial` semantics.** Compact serials come from the anchor's `(?P<serial>[A-Za-z0-9]{6,})` group; the detailed
layout has no reference column, so `serial = ""` (empty) — matching the ground truth.

---

## D7 — FFI surface (additive) + reuse of `check_balance_chain`

**Decision.** In `ffi.rs`, add two `#[uniffi::export]` functions and re-export them from `lib.rs`:
- `read_hdfc_bank_statement(lines: Vec<String>, full_text: String, first_row_words: Vec<Word>) ->
  ParsedStatement` → `read_ledger_lines(&HdfcBankReader, &lines, &full_text, &first_row_words)`.
- `hdfc_bank_claims(full_text: String) -> bool` → `claims_ledger(&HdfcBankReader, &full_text, "HDFC")`.

Reuse the **already-exported** `check_balance_chain(rows) -> ChainReport` unchanged (no second copy).

**Rationale.** Mirrors `read_icici_bank_statement` / `icici_bank_claims` exactly. **No new type crosses the
FFI** — `ParsedStatement`, `Word`, `Direction`, `LedgerMetadata`, `DirectionSource`, `ChainReport` all landed in
slice 007. Keeping the surface additive means the UniFFI `Decimal ↔ Foundation.Decimal` and `NaiveDate` bridges
and `uniffi.toml` are untouched, so `make core-xcframework` regenerates without any binding-shape change. The
`Vec<Word>` parameter is passed **empty** by the parity wrapper (HDFC sets no `column_split_x`, so geometry is
unused), but the signature stays uniform with the ICICI export for the app-side extractor.

---

## D8 — **OPEN DECISION**: `DATE_FORMATS` ordering — Rust `chrono` `%Y` vs Python `%Y` (compact 2-digit years)  ⚠️ NEEDS YOUR SIGN-OFF

**This is the single item surfaced for your decision (per your instruction to STOP rather than self-answer).**
It is a genuine correctness fork, not a style choice, and it touches **shared** code beyond the locked
`account_tail_last4`.

**Problem.** The base's `find_anchors` calls the **shared** `common.rs::parse_date` directly on the captured
`date` group. `parse_date` walks `DATE_FORMATS` in order and returns the first success. Today the list is:

```rust
// common.rs (current order)
const DATE_FORMATS: &[&str] = &[
    "%d/%m/%Y",  // index 0  ← tried first
    "%d/%m/%y",  // index 1
    // … dotted, dash, month-name, ISO …
];
```

For a **compact** token like `01/04/26`, Rust `chrono` 0.4.45's `%Y` **greedily accepts the 2-digit "26"**:

```text
NaiveDate::parse_from_str("01/04/26", "%d/%m/%Y")  ==  Ok(0026-04-01)   // Rust chrono 0.4.45 (VERIFIED)
```

So `%d/%m/%Y` **wins at index 0** and the compact rows would carry **`0026-04-01` / `0026-04-16`** — failing
parity against the ground-truth **`2026-04-01` / `2026-04-16`**. This is the **only** thing that fails in the
Rust replica before the fix (all other ~61 assertions pass).

**Root cause — a Python↔Rust `%Y` divergence.** Python's `%Y` requires **exactly 4 digits**:

```python
datetime.strptime("01/04/26", "%d/%m/%Y")   # raises ValueError → engine falls through to "%d/%m/%y" → 2026
```

That fall-through is exactly why the **web ground truth is `2026-…`**. Both formats are present in Rust's
`DATE_FORMATS` (as FR-023 assumed), but the **ordering** makes `%d/%m/%y` unreachable for pure 2-digit-year
slash tokens under Rust's greedier `%Y`.

**Recommended fix (minimal, verified safe): reorder so `%d/%m/%y` precedes `%d/%m/%Y`.**

```rust
const DATE_FORMATS: &[&str] = &[
    "%d/%m/%y",  // now index 0 — pure 2-digit-year slash dates resolve here
    "%d/%m/%Y",  // 4-digit-year slash dates fall through to here
    // … unchanged …
];
```

- **Why it's safe (VERIFIED in Rust `chrono` 0.4.45):** `%d/%m/%y` **rejects** 4-digit years —
  `parse_from_str("01/04/2026", "%d/%m/%y") == Err(…"trailing input")` — so 4-digit slash dates
  (`01/04/2026`, `30/04/2026`, `19/04/2026`) still resolve correctly via `%d/%m/%Y` at the new index 1. Dotted,
  dash, month-name, and ISO formats are untouched (different separators/shape). Every existing reader's date
  token, plus both HDFC layouts' dates and the period, parse correctly under the reordered list.
- **End-to-end proof:** with the reorder applied, the out-of-repo replica reproduces **both** HDFC fixtures
  **byte-for-byte (63/63 assertions green)**; without it, exactly the two compact **dates** are wrong.
- **Arguably a latent bug fix:** in the current order, a pure `DD/MM/YY` slash date is effectively **dead**
  (always shadowed by the greedier `%Y`), which is almost certainly not intended.

**Why this needs your call.** You locked the slice's **only** new *shared* code to `account_tail_last4`
(FR-022/023). The reorder is a **second** shared touch to `common.rs`. It's one line and verified back-compatible,
but it changes shared date-parsing order that every reader depends on, so it is not mine to self-approve.

**Alternatives (all worse):**
- **Per-config date-format hook on the base** — requires modifying the **reused-unchanged** base
  (`LedgerReaderConfig` has no date hook, and `find_anchors` calls `parse_date` directly). Rejected: base is
  reused unchanged this slice.
- **Normalise the compact `date` group before parsing** (e.g. expand `26 → 2026` in the config) — there is no
  hook point between the anchor capture and `parse_date`, and it would smuggle bank-specific logic into the base
  path. Rejected.
- **Leave as-is** — the compact fixture cannot be made green. Rejected.

**Also recommend** a one-line FR-023 / Assumptions note recording the ordering nuance (the two formats exist,
but ordering matters because Rust `%Y` is greedy), so the constraint is captured for the next reader.

**If you approve:** `/speckit.tasks` treats the reorder as a small, test-guarded task in `common.rs` (guarded by
the compact golden `Case` + a targeted `parse_date("01/04/26") == 2026-04-01` unit test, and by re-running the
ICICI/other-reader parity to prove no regression). **If you prefer another resolution**, tell me and I'll
re-plan the date handling.

---

## D9 — Bank-vs-card claim disambiguation (`claims_ledger` gate)

**Decision.** `HdfcBankReader::claim_all = ["HDFC"]`, `claim_any = ["WithdrawalAmt", "Savings Account
Details", "Statementof account"]`. `hdfc_bank_claims(full_text)` wraps `claims_ledger(&HdfcBankReader,
full_text, "HDFC")`.

**Rationale.** The repo already has an HDFC **credit-card** reader (`statement/hdfc.rs`). The savings/current
reader must **accept** bank statements and **reject** card statements (and vice-versa). `claims_ledger` requires
**all** `claim_all` tokens **and at least one** `claim_any` token — the `claim_any` set uses bank-only artifacts
(the `WithdrawalAmt.`/`DepositAmt.` column header, "Savings Account Details", the concatenated
"Statementof account" title quirk) that do not appear on HDFC card statements. Faithful to `hdfc_bank.py`'s
`claims()`.

**Verification.** Both HDFC bank fixtures' `full_text` satisfy `claim_all` + ≥1 `claim_any` → `claims == true`.
A card-style probe text (has "HDFC" but none of the bank `claim_any` tokens) → `false`. The parity harness adds
an accept/reject assertion. ✅

---

## Resolved / non-issues (checked, no action)

- **`amount_matches_delta` exactness** — the reader compares printed amount to `|delta|` **exactly**; both
  fixtures match on every row, so no suspects and no ₹1 tolerance needed (that tolerance is a `balance_chain`
  concern). Confirmed `is_suspect = false` throughout, `errored_lines = []`.
- **Two-column amount selection** — DETAILED's `withdrawal`/`deposit` pair: the base picks the **non-zero** side
  via `loose_amount`; the `0.00` side is ignored. Confirmed Debit/Credit rows resolve to `5000.00`/`50000.00`.
- **`ChainReport == Reconciled`** — for both fixtures the running balance reconciles start→end with 0 suspects
  and no row-1 fallback; `check_balance_chain` (reused) returns `Reconciled`. Confirmed in the replica.
- **Determinism** — all regexes are `LazyLock` statics; `parse_amount`/`parse_date` are pure; `regex`/`chrono`
  are locale-independent. Re-running the replica yields identical output (FR-026, SC-014).
- **No new dependency** — the reader, the helper, and the fixtures use only crates already in the graph;
  `cargo tree -e normal` is unchanged (Principle I/III, FR-034).

## Outcome

All locked decisions **verified** against the web engine, the persisted ground truth, and an out-of-repo Rust
replica (63/63 green with D8 applied). The requester's two flagged sanity items are **CONFIRMED**: the
multi-line `opening_balance_re` (D3 ✅) and the intentional header/summary narration stitching (D4 ✅). **One**
open decision remains — **D8/OD-1**, the `DATE_FORMATS` reorder — which is surfaced for your sign-off and blocks
a clean `/speckit.tasks`. No other NEEDS CLARIFICATION.
