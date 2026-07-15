# Phase 0 — Research: Yes Bank (Kiwi) Credit-Card Parser (fourth real reader, single layout, zero new infra)

**Feature**: `005-yes-cc-parser` | **Date**: 2026-07-15
**Method**: The web engine is the source of truth. Its Yes reader
(`finance-tracker-phase/backend/app/services/ingestion/statement_readers/yes_kiwi.py`) was **read as
ground truth**, and the port was **verified by running the proposed `YesReader` against the real
`kaname-core` helpers** (a throwaway crate path-depending on `kaname-core`, on the pinned stable
toolchain). Every decision below is a faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed here with
evidence. **Headline finding: Yes requires no new dependency and no new shared helper — it is a second
clean single-layout drop-in after SBI, reusing everything ICICI built and HDFC/SBI extended. The only
non-mechanical decision is the deliberate reconciliation carve-out (D10).**

---

## D1 — Reuse the ICICI/HDFC/SBI foundations wholesale; add Yes as one new module, structured like `sbi.rs`

**Decision**: Add `statement/yes.rs` (mirroring the web `yes_kiwi.py`) and touch nothing structural
elsewhere. Yes **reuses, unchanged**: the `LineReaderConfig` trait + `read_lines`/`claims` seam
(`line_reader.rs`), `ParsedStatement`/`ParsedTransaction` (`base.rs`), `parse_amount`/`parse_date`/
`find_last4` (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness
(`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom types,
`Direction` enum), and the privacy-egress gate + CI. It is structured **identically to `sbi.rs`**: a
single zero-sized `YesReader` config + a free `enrich`. Exported FFI functions live in `ffi.rs`, as
with ICICI/HDFC/SBI.

**Rationale**: The ICICI slice built this reuse surface, HDFC proved it generalizes to multi-layout,
and SBI proved a clean single-layout bank is a tiny, repeatable step. Yes is the second such drop-in;
mirroring `yes_kiwi.py → yes.rs` keeps the port a mechanical, reviewable diff.

**Alternatives**: Rebuild any shared helper for Yes — rejected: violates FR-017 and the "reuse, not
rebuild" assumption; risks parity drift.

---

## D2 — Single-layout reader: use `read_lines` directly (NOT the composite)

**Decision**: Yes has exactly **one** row layout, so `read_yes_statement` wraps
`read_lines(&YesReader, lines, full_text)` **directly** — exactly like `read_sbi_statement` and
ICICI's `read_icici_statement`. It does **not** use HDFC's `read_lines_first_match` composite (that
helper exists for multi-layout banks and is simply not needed here).

**Rationale**: The web `yes_kiwi.py` builds a single `LineStatementReader` with one `_ROW_RE`. Wrapping
the single config directly is the faithful, minimal mapping.

**Alternatives**: Route Yes through `read_lines_first_match(&[&YesReader], …)` — rejected: needless
indirection for a single layout; ICICI/SBI's direct pattern is the precedent.

---

## D3 — Row regex ported byte-for-byte; terminal `Dr`/`Cr` marker anchored at `$`

**Decision**: Port `_ROW_RE` verbatim into a `LazyLock<Regex>`:

```text
^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$
```

Named groups `date`/`desc`/`amount` match the seam's default group names; `dir` is the terminal
two-letter marker. The `read_lines` seam calls `row_re.captures(line)`; with `^…$` anchoring this is
equivalent to the web's `re.match`/`re.search` on a single line.

**Verified** (against the real crate, both golden rows):
- `29/04/2026 PAYMENT RECEIVED BBPS - Ref No: RT0001 9,000.00 Cr` → `date="29/04/2026"`,
  `desc="PAYMENT RECEIVED BBPS - Ref No: RT0001"`, `amount="9,000.00"`, `dir="Cr"`.
- `19/04/2026 UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores 100.00 Dr` →
  `desc="UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`, `amount="100.00"`, `dir="Dr"`.

**Note (merchant category → description; US1-AC3, edge case)**: the non-greedy `.+?` plus the
`\s+[\d,]+\.\d{2}\s+(Dr|Cr)$` tail forces `desc` to extend through the merchant-category phrase
(`… Ref No: RT0002 Miscellaneous Stores`) — only an *amount* can follow `desc` — so the category text
is part of the description, not a separate field. Confirmed by the verification run.

**Rationale/Alternatives**: The pattern is simple and anchored; no idiomatic deviation is needed. Rust
`regex` behaves identically to Python's `re` for this pattern (no backreferences/lookaround used).

---

## D4 — Date: `DD/MM/YYYY` is ALREADY in the shared `DATE_FORMATS` (no new date code)

**Decision**: Parse dates with the existing `common::parse_date`. The `%d/%m/%Y` format is **already**
present and, notably, **already annotated for Yes**: `common.rs:21` reads
`"%d/%m/%Y",  // 19/04/2026 (ICICI, Yes)`. `chrono`'s numeric `%d/%m/%Y` is locale-independent
(determinism).

**Verified**: `parse_date("29/04/2026") = 2026-04-29`, `"19/04/2026" = 2026-04-19`,
`"17/04/2026" = 2026-04-17`, `"16/05/2026" = 2026-05-16`. No Yes-specific date code (SC-010, US2-AC1).

**Alternatives**: A dedicated Yes date parse — rejected: the shared parser already covers it (and the
format string is the very one ICICI uses).

---

## D5 — Direction: two-letter `Dr`/`Cr` markers are ALREADY handled by `polarity::classify`

**Decision**: `direction(caps, desc) = classify(desc, caps.name("dir").map(str), None)` — identical to
`sbi.rs`/`icici.rs`, and the exact behaviour of the web's `marker_direction()`
(`polarity.classify(description, dr_cr_marker=match.group("dir"))`). No Yes-specific direction code.

**Why it already works**: `normalise_marker` filters to alphabetic/dash chars, upper-cases, and checks
the shared tables — `"Dr" → "DR"` (∈ `DR_MARKERS`), `"Cr" → "CR"` (∈ `CR_MARKERS`)
(`polarity.rs:11–12`). The explicit marker wins **before** any description-keyword check, so a
`Dr`/`Cr` marker always decides direction (FR-008/009, SC-004).

**Verified**: `Cr → Credit`, `Dr → Debit`; and a **conflicting** row
`29/04/2026 PAYMENT RECEIVED REFUND CASHBACK 500.00 Dr` classifies **Debit** — even though the
description contains three credit keywords (`PAYMENT RECEIVED`, `REFUND`, `CASHBACK`), the terminal
`Dr` marker wins (US3-AC3). Note also that the golden row 0 (`… 9,000.00 Cr`, description
`PAYMENT RECEIVED …`) is a credit both by marker and by keyword — consistent, and the marker is the
authority. Amount value/magnitude is never consulted (FR-008, US3-AC4).

**Alternatives**: A bespoke `Dr`/`Cr` rule — rejected: unnecessary; the shared classifier already maps
`Dr`/`Cr`. This is the same reuse SBI demonstrated for `C`/`D`.

---

## D6 — Enrichment: period via `_PERIOD_RE`; last-4 via the `Card Number` anchor

**Decision**: Port the enrichment faithfully into a free `enrich(statement, full_text)` — **the
period + last-4 parts only** (the printed-total scrape is dropped; see D10):

```text
_PERIOD_RE = (?i)(\d{2}/\d{2}/\d{4})\s+To\s+(\d{2}/\d{2}/\d{4})
  → statement.period_start = parse_date(g1)
    statement.period_end   = parse_date(g2)
statement.card_last4 = find_last4(full_text, Some("Card Number"))
```

`period_start` is **already** a `ParsedStatement` field (`base.rs:44`); HDFC first populated it, SBI
reused it, Yes populates it too. `find_last4`'s `anchor` path is already implemented and exercised by
HDFC/SBI. Note the Yes `_PERIOD_RE` has **no `Statement Period:` prefix** (unlike SBI's) — it matches
`<date> To <date>` case-insensitively anywhere in the text; this is a faithful port of the web regex.

**Verified** (SC-003):
- `Statement Period: 17/04/2026 To 16/05/2026` → the `(?i)…To…` pattern matches `17/04/2026` /
  `16/05/2026` → `period_start 2026-04-17`, `period_end 2026-05-16`.
- `Statement for YES BANK Card Number 3561XXXXXXXX6686` → `card_last4 = "6686"` (see D7).
- Missing metadata → fields left `None`, transactions still returned (FR-012, US4-AC3).

---

## D7 — Why `card_last4` is `"6686"` for `3561XXXXXXXX6686` (the parity point vs SBI's `None`)

**Decision/Finding**: `find_last4(full_text, Some("Card Number"))` returns **`"6686"`** — the mask
exposes **four** trailing digits, so a last-4 is recovered (contrast SBI, whose `…XX61` exposed only
two → `None`). This falls out of the existing `find_last4_in` regexes with **no Yes-specific code**:

- The anchor pass keeps lines containing `card number` (case-insensitive) — the line
  `Statement for YES BANK Card Number 3561XXXXXXXX6686` qualifies.
- `STRICT_PAN_RE = [0-9]{2,6}[Xx*]{2,}[0-9]{4}` matches `3561XXXXXXXX6686`: `3561` (leading digits),
  `XXXXXXXX` (mask run), `6686` (four trailing digits). The manual neighbour checks pass (a space
  precedes `3561`; end-of-line follows `6686`), so the strict match is accepted → last-4 `"6686"`.

**Verified**: `find_last4("… Card Number 3561XXXXXXXX6686", Some("Card Number")) = "6686"`; and the
control `find_last4("Card Number XXXX XXXX XXXX XX61", Some("Card Number")) = None` (fewer than four
trailing digits — never fabricated, FR-012). The dates (`\d{2}/\d{2}/\d{4}`) and amounts carry no mask
char, so they can never be mistaken for a PAN. Matches the web engine's `last4 = "6686"`.

---

## D8 — Amounts: exact `Decimal`, Indian grouping, scale preserved (reused `parse_amount`)

**Decision**: Amounts parse via the existing `common::parse_amount` → `rust_decimal::Decimal`, never
`f64`. Thousands separators (incl. the Indian `1,23,456` grouping) are stripped; scale is preserved.

**Verified**: `9,000.00 → 9000.00` (2dp kept), `100.00 → 100.00`, and Indian grouping
`1,23,456.78 → 123456.78`. Amounts are non-negative; direction is carried separately (FR-006/007,
SC-005).

---

## D9 — Claims / issuer plausibility; two FFI exports mirroring ICICI/HDFC/SBI

**Decision**: `BANK_CODE = "YES"`; `claim_markers = ("YES BANK",)` (a **single** marker).
`yes_claims(full_text)` delegates to `claims(&YesReader, full_text, "YES")`; `read_yes_statement`
wraps `read_lines(&YesReader, lines, full_text)`. Both are `#[uniffi::export]` in `ffi.rs` and
re-exported from `lib.rs`, mirroring the ICICI/HDFC/SBI surface (FR-018).

**Verified**: `yes_claims` claims its own doc (`YES BANK …`); rejects `ICICI Bank Statement` and
`GSTIN of SBI Card`; and the `bank_code` gate rejects a non-`YES` code even on Yes text (FR-002,
SC-002).

---

## D10 — Reconciliation carve-out: DO NOT port the printed-total scrape (the one non-mechanical decision)

**Decision**: **Do not port** the web `_enrich`'s printed per-statement debit/credit totals. The web
`yes_kiwi.py` additionally runs:

```python
_DEBITS_RE  = (?i)Purchases[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Dr
_CREDITS_RE = (?i)Payment\s*&?\s*Credits Received[^\n]*?Rs\.?\s*([\d,]+\.\d{2})\s*Cr
# → statement.printed_total_debits  = parse_amount(...)
#   statement.printed_total_credits = parse_amount(...)
```

Those two regexes and the `printed_total_*` assignments are **out of scope** for this slice and MUST
NOT appear in `statement/yes.rs`. The Rust `ParsedStatement` (`base.rs`) has **no** `printed_total_*`
fields — its doc-comment explicitly states "the reconciliation `printed_*` totals arrive with a later
slice." The Yes `enrich` here is therefore **only** period + last-4.

**Rationale**: This keeps Yes identically shaped to the landed ICICI/HDFC/SBI credit-card readers
(none expose printed totals), avoids shipping a **half-built reconciliation surface** with no
consumer, and draws a clean boundary for the dedicated reconciliation slice (spec Out of Scope). It is
a deliberate scope *reduction*, not a constitution violation (FR-013, US5, SC-013).

**Verified**: with printed-total lines appended to `full_text`
(`Purchases Rs. 100.00 Dr` / `Payment & Credits Received Rs. 9,000.00 Cr`), the Yes parse returns
**only** the two transaction rows + `period_start 2026-04-17` / `period_end 2026-05-16` /
`card_last4 "6686"` — no printed-total values appear anywhere, and the output model exposes no such
fields.

**Alternatives**: Port the totals now (naïve faithfulness) — rejected: adds fields no landed reader
uses and ships a dangling reconciliation surface. Reconciliation is a later slice; the totals belong
there.

---

## Verification harness (evidence)

A throwaway crate path-depending on the **real** `kaname-core` implemented the proposed `YesReader`
(config + `enrich` = period + last-4 only) and drove the shared `read_lines`/`claims` seam over the
golden vector. It asserted, and **all passed**:

- rows `2026-04-29 / 9000.00 / Credit / INR / "PAYMENT RECEIVED BBPS - Ref No: RT0001"` and
  `2026-04-19 / 100.00 / Debit / INR / "UPI_EXAMPLE STORE IND - Ref No: RT0002 Miscellaneous Stores"`;
  `errored_lines` empty;
- `period_start 2026-04-17`, `period_end 2026-05-16`, **`card_last4 "6686"`**; `bank_code "YES"`;
- amount scale preserved (`"9000.00"`, `"100.00"`) and Indian grouping (`1,23,456.78 → 123456.78`);
- conflicting-word row `… Dr` → Debit (marker beats `PAYMENT RECEIVED`/`REFUND`/`CASHBACK`); malformed
  row (`99/99/9999 …`) captured while the good row is returned; `claims` accept/reject + `bank_code`
  gate; byte-for-byte determinism;
- **reconciliation carve-out**: printed-total lines present ⇒ ignored (only rows + period + last-4).

The existing core suite is green on the pinned toolchain (`cargo test`: 29 unit + 6 integration/parity
tests pass), so the reused seam/helpers/harness are a stable foundation. The throwaway crate was
removed after verification (nothing committed).

---

## Resolved unknowns (summary)

| Unknown | Resolution |
|---|---|
| Module layout | `statement/yes.rs`, single `YesReader` config + free `enrich`, structured like `sbi.rs` (D1). |
| Single vs composite reader | Single layout → `read_lines(&YesReader, …)` directly, like ICICI/SBI (D2). |
| Row regex | Ported byte-for-byte; terminal `Dr`/`Cr` anchored at `$` (D3). |
| Date format | Reuse `parse_date`; `%d/%m/%Y` already present (and already commented "ICICI, Yes") (D4). |
| Direction | Reuse `classify(desc, dir, None)`; `Dr`/`Cr` already normalise to `DR`/`CR` in the polarity tables (D5). |
| Period / last-4 | `_PERIOD_RE` (no `Statement Period:` prefix, `(?i)…To…`) → `parse_date` both ends; `find_last4(_, Some("Card Number"))` (D6). |
| `card_last4` for `3561XXXXXXXX6686` | `"6686"` — four trailing digits visible; falls out of existing regexes (D7). |
| Amount format | Reuse `parse_amount`; exact `Decimal`, Indian grouping, scale preserved (D8). |
| FFI surface & claims | `read_yes_statement` + `yes_claims`, `BANK_CODE "YES"`, marker `"YES BANK"` (D9). |
| Printed-total reconciliation fields | **Not ported** — out of scope, deliberate reduction; ParsedStatement has no such fields (D10, FR-013). |
| New dependency / new shared helper | **None** — pure drop-in (D1, plan Constitution Check). |
