# Contract: `HdfcBankReader` config + the shared `account_tail_last4` helper (+ ICICI refactor)

**Feature**: `008-hdfc-bank-ledger-reader` | **Phase 1** | **Plan**: [`plan.md`](../plan.md)

Specifies the new HDFC configuration against the **reused-unchanged** `LedgerReaderConfig` base, the sole new
**shared** helper, and the behaviour-preserving ICICI refactor. Faithful port of `hdfc_bank.py`.

## A. `HdfcBankReader impl LedgerReaderConfig` (`src/statement/hdfc_bank.rs`, NEW)

Zero-sized unit struct; all behaviour via `LazyLock<Regex>` statics + trait methods (mirror
`IciciBankReader`).

### A.1 Anchors — **two**, ordered, first-match-wins

`anchor_res()` returns `vec![&COMPACT_RE, &DETAILED_RE]` (in this order). The base tries them per line and uses
the first that matches (HDFC is the first config to supply >1 anchor).

```text
COMPACT_RE
  ^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<desc>.*?)\s+(?P<serial>[A-Za-z0-9]{6,})\s+\d{2}/\d{2}/\d{2}\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$

DETAILED_RE
  ^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.*?)\s+(?P<withdrawal>[\d,]+\.\d{2})\s+(?P<deposit>[\d,]+\.\d{2})\s+(?P<balance>[\d,]+\.\d{2})\s*$
```

**Capture-group contract** (consumed by the base):
- COMPACT → `date`, `desc`, `serial`, `amount`, `balance`. The base's `anchor_amount` uses the single `amount`;
  `serial` is recorded on the row's `ledger.serial`. (There is also a bare value-date `\d{2}/\d{2}/\d{2}`
  between `serial` and `amount` — matched but **not** captured.)
- DETAILED → `date`, `desc`, `withdrawal`, `deposit`, `balance`. `anchor_amount` picks the **non-zero** of
  `withdrawal`/`deposit` via `loose_amount` (empty side is `0.00`). No `serial` group ⇒ `serial = ""`.
- **Mutual exclusion**: COMPACT requires a 2-digit year, DETAILED a 4-digit year ⇒ no row matches both
  (verified against both fixtures).

### A.2 Balance anchors

```text
opening_balance_re() = Some(OPENING_RE)
  OPENING_RE  (?i)(?:Opening Balance\s*:\s*|OpeningBalance\b[^\n]*\n\s*)([\d,]+\.\d{2})
closing_balance_re() = None
```

- **Group 1** is the opening balance in **both** alternatives:
  - **alt 1** matches the **detailed** inline `Opening Balance : 1,00,000.00`.
  - **alt 2** matches the **compact** end-of-statement summary spanning a newline
    (`OpeningBalance … ClosingBal\n1,00,000.00 …`) — Rust `regex` `\n`/`[^\n]` work **without** multiline/`(?s)`.
- **Closing** is derived from the final row's balance (no closing regex) ⇒ `printed_closing_balance =
  145000.00`.

### A.3 Geometry

```text
column_split_x() = None
```

HDFC needs no x-split; `first_row_words` is unused (passed empty).

### A.4 Enrichment (`enrich(full_text, out)`)

```text
PERIOD_RE       (?i)From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:?\s*(\d{2}/\d{2}/\d{4})
HDFC_ACCOUNT_RE (?i)Account\s*(?:Number|No\.?)\s*:?\s*X*([0-9]{4,})
```

- **Period** — `PERIOD_RE` groups 1 & 2 → `parse_date` → `period_start = 2026-04-01`, `period_end =
  2026-04-30`. The **`:?` after `To`** is required: the detailed preamble is `… To 30/04/2026` (no colon), the
  compact is `… To : 30/04/2026` (colon). Both period dates are 4-digit (`%d/%m/%Y`), unaffected by OD-1.
- **Account last-4** — `card_last4 = account_tail_last4(full_text, &HDFC_ACCOUNT_RE)`. HDFC differences vs
  ICICI (faithful to `hdfc_bank.py`): `Account\s*` (not `\s+`) so it matches the concatenated `AccountNo`;
  optional masked `X*` prefix; **4+** digits (`[0-9]{4,}`). Both fixtures → group 1 `50100359253425` → `3425`.

### A.5 Identity / claims

```text
BANK_CODE  = "HDFC"
claim_all  = ["HDFC"]
claim_any  = ["WithdrawalAmt", "Savings Account Details", "Statementof account"]
```

`claims_ledger` accepts iff all `claim_all` **and** ≥1 `claim_any`. Must reject HDFC **credit-card** statements
(separate reader `statement/hdfc.rs`).

### A.6 Wiring

`src/statement/mod.rs`: add `pub mod hdfc_bank;`.

## B. Shared helper `account_tail_last4` (`src/statement/common.rs`, NEW — the ONLY new shared code)

```rust
/// Trailing 4 digits of an account/card number.
/// 1) `primary` capture group 1 → last 4 of its digits, else
/// 2) the longest standalone run of ≥9 digits (DIGIT_RUN_RE `\d{9,}`) → last 4, else
/// 3) None.
pub fn account_tail_last4(text: &str, primary: &Regex) -> Option<String>;
```

- Moves the existing `last4` (trailing-4) + `DIGIT_RUN_RE` ("longest `\d{9,}` run") logic out of
  `icici_bank.rs` into `common.rs`, alongside `parse_amount`/`parse_date`/`find_last4`.
- The `\d{9,}` fallback reproduces Python's `(?<!\d)(\d{9,})(?!\d)` "longest run": greedy **non-overlapping**
  `\d{9,}` yields maximal runs; `max_by_key(len)` picks the longest.
- **Consumers**: `HdfcBankReader` (via `HDFC_ACCOUNT_RE`) and `IciciBankReader` (via `ICICI_ACCOUNT_RE`, §C).
  No other new shared code.

## C. ICICI refactor (`src/statement/icici_bank.rs`, CHANGED — behaviour-preserving)

- Replace ICICI's local account logic with:
  `account_tail_last4(full_text, &ICICI_ACCOUNT_RE)` where
  `ICICI_ACCOUNT_RE = (?i)Account\s+(?:Number|No\.?)\s*:?\s*([0-9]{6,})` (ICICI keeps `\s+`, no `X*`, `{6,}`).
- Drop the now-unused local `last4` / `DIGIT_RUN_RE` / `account_tail`.
- **Invariant**: the ICICI golden fixture stays **GREEN** — verified `000401000123456 → 3456` (unchanged).

## D. `common.rs::DATE_FORMATS` reorder — **PENDING OD-1** (needs sign-off)

- Move `"%d/%m/%y"` **before** `"%d/%m/%Y"` so the compact 2-digit-year dates parse to `2026-…` (Rust
  `chrono`'s `%Y` greedily accepts 2 digits; `%d/%m/%y` rejects 4-digit years, so 4-digit slash dates still
  resolve). See research **D8** / plan **Open Decisions**. Not applied without approval.

## Determinism & purity (base guarantees, reused)

- All regexes are `LazyLock` statics; `parse_amount`/`parse_date` are pure; `regex`/`chrono` are
  locale-independent ⇒ identical output across runs (FR-026, SC-014).
- No I/O, no network, no PDF; money is `Decimal`; direction is delta-derived with `direction_source`.

## Behavioural checklist (verified in an out-of-repo Rust replica, 63/63 green with OD-1)

- [x] COMPACT/DETAILED anchors match their own fixture rows only (mutual exclusion).
- [x] `serial` = `0000600000000001` / `CITIN26653417445` (compact); `""` (detailed).
- [x] Two-column amount picks the non-zero side (detailed).
- [x] `OPENING_RE` group 1 = `100000.00` for **both** layouts (compact via newline alt).
- [x] `printed_closing_balance = 145000.00` (final row balance).
- [x] Period `2026-04-01 → 2026-04-30` (optional colon after `To`).
- [x] `account_tail_last4` → `3425` (HDFC, both) and `3456` (ICICI back-compat).
- [x] Narrations stitched byte-for-byte (see golden-fixture contract).
- [x] Chain `Reconciled`; `errored_lines == []`; all rows `is_suspect == false`, `amount_matches_delta == true`.
