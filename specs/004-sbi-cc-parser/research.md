# Phase 0 — Research: SBI Card Credit-Card Parser (third real reader, single layout, zero new infra)

**Feature**: `004-sbi-cc-parser` | **Date**: 2026-07-15
**Method**: The web engine is the source of truth. Its SBI reader
(`finance-tracker-phase/backend/app/services/ingestion/statement_readers/sbi_card.py`) and the
characterization vector (`test_cc_reader_characterization.py`, `_SBI_LINES`/`_SBI_TEXT`) were
**read as ground truth**, and the port was **verified by running the proposed `SbiReader` against
the real `kaname-core` helpers** (a throwaway project path-depending on the crate, on the pinned
stable toolchain). Every decision below is a faithful port or a justified, verified idiomatic
mapping.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed here
with evidence. **Headline finding: SBI requires no new dependency and no new shared helper — it is
a pure single-layout drop-in reusing everything ICICI built and HDFC extended.**

---

## D1 — Reuse the ICICI/HDFC foundations wholesale; add SBI as one new module, structured like `icici.rs`

**Decision**: Add `statement/sbi.rs` (mirroring the web `sbi_card.py`) and touch nothing structural
elsewhere. SBI **reuses, unchanged**: the `LineReaderConfig` trait + `read_lines`/`claims` seam
(`line_reader.rs`), `ParsedStatement`/`ParsedTransaction` (`base.rs`), `parse_amount`/`parse_date`/
`find_last4` (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness
(`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom
types, `Direction` enum), and the privacy-egress gate + CI. It is structured **identically to
`icici.rs`**: a single zero-sized `SbiReader` config + a free `enrich`. Exported FFI functions live
in `ffi.rs`, as with ICICI/HDFC.

**Rationale**: The ICICI slice built this reuse surface and HDFC proved it generalizes; SBI is the
slice that proves adding a bank is now a *tiny, repeatable* step. Mirroring `sbi_card.py → sbi.rs`
keeps the port a mechanical, reviewable diff.

**Alternatives**: Rebuild any shared helper for SBI — rejected: violates FR-017 and the
"reuse, not rebuild" assumption; risks parity drift.

---

## D2 — Single-layout reader: use `read_lines` directly (NOT the composite)

**Decision**: SBI has exactly **one** row layout, so `read_sbi_statement` wraps
`read_lines(&SbiReader, lines, full_text)` **directly** — exactly like ICICI's
`read_icici_statement`. It does **not** use HDFC's `read_lines_first_match` composite (that helper
exists for multi-layout banks and is simply not needed here).

**Rationale**: The web `sbi_card.py` builds a single `LineStatementReader` and calls its
`read_lines`; there is one `_ROW_RE`. Wrapping the single config directly is the faithful,
minimal mapping.

**Alternatives**: Route SBI through `read_lines_first_match(&[&SbiReader], …)` — rejected:
needless indirection for a single layout; ICICI's direct pattern is the precedent.

---

## D3 — Row regex ported byte-for-byte; terminal `C`/`D` marker anchored at `$`

**Decision**: Port `_ROW_RE` verbatim into a `LazyLock<Regex>`:

```text
^(?P<date>\d{2} [A-Za-z]{3} \d{2})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>[CD])$
```

Named groups `date`/`desc`/`amount` match the seam's default group names; `dir` is the terminal
single-letter marker. The `read_lines` seam calls `row_re.captures(line)`; with `^…$` anchoring
this is equivalent to the web's `re.search` on a single line.

**Verified** (against the real crate, both golden rows):
- `21 Apr 26 CARD CASHBACK CREDIT 643.00 C` → `date="21 Apr 26"`, `desc="CARD CASHBACK CREDIT"`,
  `amount="643.00"`, `dir="C"`.
- `20 May 26 APPLE INDIA STORE MUMBAI IN 82,900.00 D` → `desc="APPLE INDIA STORE MUMBAI IN"`,
  `amount="82,900.00"`, `dir="D"`.

**Note (US3-AC3)**: row 1's description ends in the word **"CREDIT"**, yet the non-greedy `.+?`
plus the `\s+[\d,]+\.\d{2}\s+[CD]$` tail forces `desc` to extend through "CREDIT" (only an *amount*
can follow `desc`), so the split is correct **and** the direction still comes from the terminal
`C` marker — not the word. Confirmed by the verification run.

**Rationale/Alternatives**: The pattern is simple and anchored; no idiomatic deviation is needed.
Rust `regex` has no backreferences here and behaves identically to Python's `re` for this pattern.

---

## D4 — Date: `DD Mon YY` is ALREADY in the shared `DATE_FORMATS` (no new date code)

**Decision**: Parse dates with the existing `common::parse_date`. The `%d %b %y` format is already
present (`common.rs:26`, commented "21 Apr 26 (SBI)"). `chrono`'s `%b` uses built-in English month
tables, so parsing is locale-independent (determinism).

**Verified**: `parse_date("21 Apr 26") = 2026-04-21`, `"20 May 26" = 2026-05-20`,
`"22 Apr 26" = 2026-04-22`, `"21 May 26" = 2026-05-21`. No SBI-specific date code (SC-010, US2-AC1).

**Alternatives**: A dedicated SBI date parse — rejected: the shared parser already covers it.

---

## D5 — Direction: single-letter `C`/`D` markers are ALREADY handled by `polarity::classify`

**Decision**: `direction(caps, desc) = classify(desc, caps.name("dir").map(str), None)` — identical
to `icici.rs`, and the exact behavior of the web's `marker_direction()`
(`polarity.classify(description, dr_cr_marker=match.group("dir"))`). No SBI-specific direction code.

**Why it already works**: `normalise_marker` filters to alphabetic/dash chars, upper-cases, and
checks the shared tables — `CR_MARKERS` contains `"C"` and `DR_MARKERS` contains `"D"`
(`polarity.rs:11–12`). The explicit marker wins **before** any description-keyword check, so a
`C`/`D` marker always decides direction (FR-008/009, SC-004).

**Verified**: `C → Credit`, `D → Debit`; and a **conflicting** row
`… REFUND CREDIT ADJUSTMENT … D` classifies **Debit** (marker beats the credit-language in the
description), proving direction is never taken from the wording (US3-AC3). Amount value/magnitude is
never consulted (FR-008, US3-AC4).

**Alternatives**: A bespoke `C`/`D` rule (like HDFC's monthly leading-`+`) — rejected: unnecessary;
the shared classifier already maps `C`/`D`. This is the deliberate contrast with HDFC.

---

## D6 — Enrichment: period via `_PERIOD_RE`; last-4 via the `Credit Card Number` anchor

**Decision**: Port `_enrich` faithfully into a free `enrich(statement, full_text)`:

```text
_PERIOD_RE = (?i)Statement Period:\s*(\d{2} [A-Za-z]{3} \d{2})\s+to\s+(\d{2} [A-Za-z]{3} \d{2})
  → statement.period_start = parse_date(g1)
    statement.period_end   = parse_date(g2)
statement.card_last4 = find_last4(full_text, Some("Credit Card Number"))
```

`period_start` is **already** a `ParsedStatement` field (`base.rs:44`); HDFC first populated it, SBI
populates it too. `find_last4`'s `anchor` path is already implemented and exercised by HDFC.

**Verified** (SC-003):
- `for Statement Period: 22 Apr 26 to 21 May 26` → `period_start 2026-04-22`, `period_end 2026-05-21`.
- `Credit Card Number XXXX XXXX XXXX XX61` → **`card_last4 = None`** (see D7).
- When 4 trailing digits are visible (`… XXXX XXXX XXXX 1234`) → `card_last4 = "1234"` (US4-AC3).
- Missing metadata → fields left `None`, transactions still returned (FR-013, US4-AC4).

---

## D7 — Why `card_last4` is `None` for `XXXX XXXX XXXX XX61` (the subtle parity point)

**Decision/Finding**: `find_last4` returns `None` for a mask that exposes **fewer than four**
trailing digits, and it is **never fabricated** (FR-012, SC-003, US4-AC2). This falls out of the
existing `find_last4_in` regexes with **no SBI-specific code**:

- `STRICT_PAN_RE = [0-9]{2,6}[Xx*]{2,}[0-9]{4}` requires **four contiguous trailing digits** — the
  mask ends in `XX61` (two digits), and the groups are space-separated, so no strict match.
- `LOOSE_PAN_RE = (?:[0-9Xx*][ \-]?){12,}[0-9]{4}` also requires a trailing run of **four digits**;
  the tail is `…XX61` (only `61`), so no loose match either. (The newline after `XX61` also blocks
  the `[ \-]?` separator from bridging into the next line.)

**Verified**: `find_last4("Credit Card Number XXXX XXXX XXXX XX61", Some("Credit Card Number"))`
and the whole-text fallback both return `None`. The amounts (`643.00`, `82,900.00`) and dates carry
no mask char, so they can never be mistaken for a PAN. Matches the web engine's `last4 = None`.

---

## D8 — Amounts: exact `Decimal`, Indian grouping, scale preserved (reused `parse_amount`)

**Decision**: Amounts parse via the existing `common::parse_amount` → `rust_decimal::Decimal`, never
`f64`. Thousands separators (incl. the Indian `1,23,456` grouping) are stripped; scale is preserved.

**Verified**: `82,900.00 → 82900.00` (2dp kept), `643.00 → 643.00`, and Indian grouping
`1,23,456.78 → 123456.78`. Amounts are non-negative; direction is carried separately (FR-006/007,
SC-005).

---

## D9 — Claims / issuer plausibility; two FFI exports mirroring ICICI/HDFC

**Decision**: `BANK_CODE = "SBI_CARD"`; `claim_markers = ("SBI Card", "GSTIN of SBI Card")`.
`sbi_claims(full_text)` delegates to `claims(&SbiReader, full_text, "SBI_CARD")`; `read_sbi_statement`
wraps `read_lines(&SbiReader, lines, full_text)`. Both are `#[uniffi::export]` in `ffi.rs` and
re-exported from `lib.rs`, mirroring the ICICI/HDFC surface (FR-018).

**Note**: `claims` also matches `"SBI Card"` as a substring of `"GSTIN of SBI Card"`, exactly as the
web tuple does; both markers are retained for faithfulness. **Verified**: claims its own doc; rejects
`ICICI Bank Statement` and `HDFC Bank Credit Cards`; and the `bank_code` gate rejects a non-`SBI_CARD`
code even on SBI text (FR-002, SC-002).

---

## Verification harness (evidence)

A throwaway binary path-depending on the **real** `kaname-core` crate implemented the proposed
`SbiReader` (config + `enrich`) and drove the shared `read_lines`/`claims` seam over the golden
vector. It asserted, and **all passed**:

- rows `2026-04-21 / 643.00 / Credit / INR / "CARD CASHBACK CREDIT"` and
  `2026-05-20 / 82900.00 / Debit / INR / "APPLE INDIA STORE MUMBAI IN"`; `errored_lines` empty;
- `period_start 2026-04-22`, `period_end 2026-05-21`, **`card_last4 None`**; `bank_code "SBI_CARD"`;
- amount scale preserved (`"82900.00"`, `"643.00"`) and Indian grouping (`1,23,456.78 → 123456.78`);
- conflicting-word row `… D` → Debit (marker beats description); malformed row captured while the
  good row is returned; `claims` accept/reject + `bank_code` gate; and byte-for-byte determinism.

The existing core suite is green on the pinned toolchain (`cargo test`: 27 unit + 5 integration/
parity tests pass), so the reused seam/helpers/harness are a stable foundation. The throwaway
project was removed after verification (nothing committed).

---

## Resolved unknowns (summary)

| Unknown | Resolution |
|---|---|
| Module layout | `statement/sbi.rs`, single `SbiReader` config + free `enrich`, structured like `icici.rs` (D1). |
| Single vs composite reader | Single layout → `read_lines(&SbiReader, …)` directly, like ICICI (D2). |
| Row regex | Ported byte-for-byte; terminal `C`/`D` anchored at `$` (D3). |
| Date format | Reuse `parse_date`; `%d %b %y` already present (D4). |
| Direction | Reuse `classify(desc, dir, None)`; `C`/`D` already in the polarity tables (D5). |
| Period / last-4 | `_PERIOD_RE` → `parse_date` both ends; `find_last4(_, Some("Credit Card Number"))` (D6). |
| `card_last4` for a 2-digit mask | `None` — falls out of existing regexes, never fabricated (D7). |
| Amount format | Reuse `parse_amount`; exact `Decimal`, Indian grouping, scale preserved (D8). |
| FFI surface & claims | `read_sbi_statement` + `sbi_claims`, `BANK_CODE "SBI_CARD"`, markers `SBI Card`/`GSTIN of SBI Card` (D9). |
| New dependency / new shared helper | **None** — pure drop-in (D1, plan Constitution Check). |
