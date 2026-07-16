# Phase 0 — Research: Federal Bank / Scapia Credit-Card Parser (fifth & final reader, single layout, zero new infra)

**Feature**: `006-federal-cc-parser` | **Date**: 2026-07-16
**Method**: The web engine is the source of truth. Its Federal reader
(`finance-tracker-phase/backend/app/services/ingestion/statement_readers/federal_scapia.py`) was
**read as ground truth**, and the port was **verified by running the proposed `FederalReader` against
the real `kaname-core` helpers** (a throwaway crate path-depending on `kaname-core`, on the pinned
stable toolchain, rustc 1.96.1). Every decision below is a faithful port or a justified, verified
idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed here with
evidence. **Headline finding: Federal — the most distinctive of the five layouts — requires no new
dependency and no new shared helper. Both its date formats are already in the shared date parser, its
credit-word fallback reuses the shared classifier, and its one bespoke rule (leading-`+` credit) is the
same in-reader pattern HDFC's monthly layout already uses. The two things worth verifying — the
middot `.` match and the un-anchored `find_last4` — both behave correctly (D3, D7).**

---

## D1 — Reuse the ICICI/HDFC/SBI/Yes foundations wholesale; add Federal as one new module, structured like `sbi.rs`/`yes.rs`

**Decision**: Add `statement/federal.rs` (mirroring the web `federal_scapia.py`) and touch nothing
structural elsewhere. Federal **reuses, unchanged**: the `LineReaderConfig` trait + `read_lines`/
`claims` seam (`line_reader.rs`), `ParsedStatement`/`ParsedTransaction` (`base.rs`), `parse_amount`/
`parse_date`/`find_last4` (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness
(`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom types,
`Direction` enum), and the privacy-egress gate + CI. It is structured **like `sbi.rs`/`yes.rs`**: a
single zero-sized `FederalReader` config + an `enrich`. Exported FFI functions live in `ffi.rs`, as
with ICICI/HDFC/SBI/Yes.

**Rationale**: The ICICI slice built this reuse surface; HDFC proved it generalizes to multi-layout and
to a leading-`+` direction rule; SBI and Yes proved a clean single-layout bank is a tiny, repeatable
step. Federal is the third such single-layout drop-in and **completes the credit-card set**; mirroring
`federal_scapia.py → federal.rs` keeps the port a mechanical, reviewable diff.

**Alternatives**: Rebuild any shared helper for Federal — rejected: violates FR-018 and the "reuse, not
rebuild" assumption; risks parity drift.

---

## D2 — Single-layout reader: use `read_lines` directly (NOT the composite)

**Decision**: Federal has exactly **one** row layout, so `read_federal_statement` wraps
`read_lines(&FederalReader, lines, full_text)` **directly** — exactly like `read_sbi_statement` /
`read_yes_statement` and ICICI's `read_icici_statement`. It does **not** use HDFC's
`read_lines_first_match` composite (that helper exists for multi-layout banks and is simply not needed
here).

**Rationale**: The web `federal_scapia.py` builds a single `LineStatementReader` with one `_ROW_RE`.
Wrapping the single config directly is the faithful, minimal mapping.

**Alternatives**: Route Federal through `read_lines_first_match(&[&FederalReader], …)` — rejected:
needless indirection for a single layout; ICICI/SBI/Yes's direct pattern is the precedent.

---

## D3 — Row regex ported byte-for-byte; the unescaped `.` matches the middot separator encoding-robustly

**Decision**: Port `_ROW_RE` verbatim into a `LazyLock<Regex>` (a raw UTF-8 string literal, so the `₹`
is a literal char in the pattern):

```text
^(?P<date>\d{2}-\d{2}-\d{4}).\d{2}:\d{2}\s+(?P<desc>.+?)\s+(?P<sign>\+)?₹(?P<amount>[\d,]+\.\d{2})$
```

- Named groups `date`/`desc`/`amount` match the seam's default group names; the extra `sign` group is
  read by the reader's `direction` (the seam passes the full `Captures` to `direction`, so **no seam
  change** is needed).
- The **unescaped `.`** immediately after the date group matches the **middle-dot** date/time
  separator (U+00B7) **encoding-robustly**. Rust `regex`'s default `.` matches **any single
  non-newline Unicode scalar**, so it matches `·` regardless of which glyph/bytes native text
  extraction produced for the separator (FR-004, SC-005).
- The `HH:MM` transaction time is consumed by `\d{2}:\d{2}` and **never** enters `desc` (FR-005).
- The literal `₹` (U+20B9) precedes the amount group and is **excluded** from `amount` (`[\d,]+\.\d{2}`
  captures only the digits/commas/point), so `parse_amount` sees a clean money token (FR-008).
- The `(?P<sign>\+)?` is the **optional** leading `+`, captured (not consumed by `desc`) so `direction`
  can test it.

**Verified** (against the real crate, both golden rows):
- `29-04-2026·16:18 Billpayment Payment +₹324.45` → `date="29-04-2026"`, `desc="Billpayment Payment"`,
  `sign=Some("+")`, `amount="324.45"`.
- `24-04-2026·06:03 ExampleMerchantTokyo ₹2,353.13` → `date="24-04-2026"`,
  `desc="ExampleMerchantTokyo"`, `sign=None`, `amount="2,353.13"`.
- **Encoding-robustness**: the same row still matches with the separator swapped for a plain ASCII
  space (`29-04-2026 16:18 …`) and for a literal dot (`29-04-2026.16:18 …`) — both `is_match == true`.
  This is the whole point of the unescaped `.` and satisfies FR-004/SC-005.

**Note (non-greedy `desc`)**: the non-greedy `.+?` plus the `\s+(?P<sign>\+)?₹…$` tail forces `desc` to
stop right before the ` [+]₹<amount>` — only the optional `+`/`₹`/amount tail can follow — so multi-word
merchant descriptions (`Billpayment Payment`) are captured whole. Confirmed by the verification run.

**Rationale/Alternatives**: The pattern is simple and anchored (`^…$`); no idiomatic deviation is
needed. Escaping the separator as an explicit `\x{00B7}` was **rejected** — it would defeat the
encoding-robustness the web engine deliberately relies on (any single char). Rust `regex` behaves
identically to Python's `re` here (no backreferences/lookaround used).

---

## D4 — Row date: `%d-%m-%Y` is ALREADY in the shared `DATE_FORMATS` (no new date code)

**Decision**: Parse row dates with the existing `common::parse_date`. The `%d-%m-%Y` format is
**already** present and **already annotated for this reader**: `common.rs:24` reads
`"%d-%m-%Y",  // 24-04-2026 (Scapia/Federal)`. `chrono`'s numeric `%d-%m-%Y` is locale-independent
(determinism).

**Verified**: `parse_date("29-04-2026") = 2026-04-29`, `"24-04-2026" = 2026-04-24`. No Federal-specific
date code (SC-011, US2-AC1).

**Alternatives**: A dedicated Federal date parse — rejected: the shared parser already covers it (and
the format string was pre-seeded for Scapia/Federal).

---

## D5 — Billing cycle: `%d%b%Y` (space-stripped) is ALREADY in the shared `DATE_FORMATS`

**Decision**: Parse the billing-cycle dates with the existing `common::parse_date`. The space-stripped
`%d%b%Y` format is **already** present and **already annotated for this reader**: `common.rs:31` reads
`"%d%b%Y",    // 20Apr2026 (Scapia billing cycle, space-stripped)`. `chrono`'s `%b` uses a built-in
English month table, so parsing is locale-independent.

**Verified**: `parse_date("20Apr2026") = 2026-04-20`, `parse_date("19May2026") = 2026-05-19`. No
Federal-specific date code (SC-011, US2-AC2).

---

## D6 — Direction: Federal-LOCAL leading-`+` rule, else the shared classifier (NOT the shared marker path)

**Decision**: `direction(caps, desc)` is Federal-local, ported from the web `_direction`:

```rust
if caps.name("sign").map(|m| m.as_str()) == Some("+") {
    Direction::Credit                 // Scapia's own credit notation
} else {
    classify(description, None, None) // shared description-language fallback
}
```

This is **NOT** the `classify(desc, caps.name("dir"), None)` marker path ICICI/SBI/Yes use — Scapia has
**no** `Dr`/`Cr` column. The `+` test lives in the reader; the fallback reuses the shared classifier
unchanged (credit words → Credit; else Debit). The amount's value/magnitude is **never** consulted.

**Why this is precedented, not new infra**: HDFC's **monthly** layout already decides direction in-reader
by inspecting a leading-`+` capture (`hdfc.rs` `HdfcMonthly::direction`: `caps.name("dir")…starts_with('+')`).
Federal uses the identical pattern (a captured `sign` group), differing only in that its non-`+` case
falls through to `classify(…)` rather than defaulting straight to Debit — which is exactly what the web
`_direction` does. So this is a **known, landed pattern**, not a new shared helper (FR-010/011, SC-011).

**Verified**:
- Golden row 0 (`… +₹324.45`, `sign=Some("+")`) → **Credit** — even though `Billpayment Payment` is not
  a recognized credit phrase, the `+` is decisive (US3-AC1).
- Golden row 1 (`… ₹2,353.13`, `sign=None`, `ExampleMerchantTokyo`) → **Debit** via the classifier's
  default (US3-AC2).
- A no-`+` `Refund reversal received` row → **Credit** via the shared classifier's credit keywords
  (US3-AC3). Confirmed by the verification run.
- Amount value/magnitude is never consulted (FR-010, US3-AC4).

**Alternatives**: Add a `+`-as-credit case to the shared `normalise_marker`/`classify` — **rejected**:
that would be a new shared-subsystem behaviour for a one-issuer notation (violates FR-018/SC-011) and
could leak `+`-credit into readers that don't want it. Keep it in `federal.rs`.

---

## D7 — `card_last4`: the UN-ANCHORED `find_last4(full_text, None)` yields `"4836"` (the parity point to sanity-check)

**Decision/Finding**: The card is **fully masked with no textual label** (`XXXXXXXXXXXX4836`), so
Federal calls `find_last4(full_text, None)` — **no anchor** — scanning the whole text (a faithful port
of the web `_common.find_last4(full_text)`, which passes no anchor). This returns **`"4836"`** and is
**not** confused by other digits/letters in the document. It falls out of the existing `find_last4_in`
regexes with **no Federal-specific code**:

- With `anchor=None`, `find_last4` goes straight to `find_last4_in(full_text)`.
- `STRICT_PAN_RE = [0-9]{2,6}[Xx*]{2,}[0-9]{4}` requires **leading digits before the mask** — but
  `XXXXXXXXXXXX4836` has none (it starts with 12 X's), so the strict pass finds nothing. (It is also
  **not** tripped by the lowercase `x` in `ExampleMerchantTokyo`: that is a **single** `x`, and
  `[Xx*]{2,}` needs two or more consecutive mask chars, with 2–6 digits before and 4 after — none of
  which the merchant word supplies.)
- The fallback `LOOSE_PAN_RE = (?:[0-9Xx*][ \-]?){12,}[0-9]{4}` matches the 12 `X`s + `4836`; the
  extracted digits are `"4836"` → last-4 `"4836"`. The greedy `{12,}` cannot bridge into the following
  ` 20Apr2026-19May2026` because the letters `Apr` break the PAN-char run, so the match is exactly
  `XXXXXXXXXXXX4836` and the last-4 is unambiguously `"4836"` (not `3620` or a year fragment).

**Verified** (against the real crate):
- `find_last4("Scapia by Federal Bank\nXXXXXXXXXXXX4836 20Apr2026-19May2026\n<rows>", None) =
  Some("4836")`.
- With **no** masked card present (just the two transaction lines), `find_last4(…, None) = None`
  (never fabricated — FR-014, US4-AC3). This confirms the un-anchored scan does not mistake dates,
  the `HH:MM` times, or the merchant word's `x` for a card number.

**Why no anchor (contrast with SBI/Yes)**: SBI/Yes call `find_last4(full_text, Some("Card Number"))`
because their statements print a `Card Number` label. Federal's masked PAN has **no** such label, so an
anchor would filter to zero lines and fall back to the whole text anyway — passing `None` is the
faithful, direct port and is exactly what the web reader does.

---

## D8 — Amounts: exact `Decimal`, rupee glyph + `+` stripped, Indian grouping, scale preserved (reused `parse_amount`)

**Decision**: Amounts parse via the existing `common::parse_amount` → `rust_decimal::Decimal`, never
`f64`. The regex already excludes the `₹` and the `+` from the `amount` group; `parse_amount`
additionally strips any `₹`/`Rs`/`INR`/thousands separators (incl. the Indian `1,23,456` grouping) and
preserves scale.

**Verified**: `+₹324.45 → 324.45` (2dp kept), `₹2,353.13 → 2353.13` (comma stripped, scale preserved).
Amounts are non-negative; direction is carried separately (FR-008/009, SC-006).

---

## D9 — Claims / issuer plausibility; two FFI exports mirroring ICICI/HDFC/SBI/Yes

**Decision**: `BANK_CODE = "FEDERAL"`; `claim_markers = ("Scapia", "Federal Bank")` (**two** markers,
a faithful port). `federal_claims(full_text)` delegates to `claims(&FederalReader, full_text,
"FEDERAL")`; `read_federal_statement` wraps `read_lines(&FederalReader, lines, full_text)`. Both are
`#[uniffi::export]` in `ffi.rs` and re-exported from `lib.rs`, mirroring the ICICI/HDFC/SBI/Yes surface
(FR-019).

**Verified**: `federal_claims` claims its own doc (`Scapia by Federal Bank …`); rejects
`ICICI Bank Statement`, `HDFC Bank Credit Cards`, `GSTIN of SBI Card`, and `YES BANK KLICK`; and the
`bank_code` gate rejects a non-`FEDERAL` code even on Federal text (FR-002, SC-002).

---

## D10 — No reconciliation carve-out needed (unlike Yes) — the web `_enrich` is already cycle + last-4 only

**Decision/Finding**: Unlike the Yes port (which had to **drop** the web reader's printed-total scrape),
Federal's web `_enrich` **already** does only two things — the billing cycle and the card last-4:

```python
def _enrich(statement, full_text):
    match = _CYCLE_RE.search(full_text)
    if match:
        statement.period_start = _common.parse_date(match.group(1))
        statement.period_end   = _common.parse_date(match.group(2))
    statement.card_last4 = _common.find_last4(full_text)
```

There are **no** `printed_total_*` regexes or assignments in `federal_scapia.py`, so the Rust port is a
**1:1 mechanical match** with nothing dropped and nothing added. The Rust `ParsedStatement` already
carries exactly these fields (`period_start`/`period_end`/`card_last4`), so no model change is needed.

**Rationale**: Recording this explicitly so a reviewer expecting a Yes-style carve-out sees there isn't
one — Federal is even simpler.

---

## Verification harness (evidence)

A throwaway crate path-depending on the **real** `kaname-core` implemented the proposed `FederalReader`
(config + `enrich` = cycle + un-anchored last-4) and drove the shared `read_lines`/`claims` seam over
the golden vector. It asserted, and **all passed**:

- rows `2026-04-29 / 324.45 / Credit / INR / "Billpayment Payment"` and
  `2026-04-24 / 2353.13 / Debit / INR / "ExampleMerchantTokyo"`; `errored_lines` empty;
- `period_start 2026-04-20`, `period_end 2026-05-19`, **`card_last4 "4836"`** (un-anchored);
  `bank_code "FEDERAL"`;
- the row matches **encoding-robustly** with the date/time separator as `·`, a plain space, or `.`
  (all `is_match`);
- amount scale preserved (`"324.45"`, `"2353.13"`) with the `₹`/`+` stripped and the Indian comma
  removed;
- direction: `+` → Credit; no-`+` ordinary spend → Debit; no-`+` `refund/reversal received` → Credit
  (shared classifier); amount magnitude never consulted;
- `find_last4` returns `None` when no masked card is present (never fabricated) and is not tripped by
  the lowercase `x` in `ExampleMerchantTokyo` or the `20Apr2026-…` range on the same line;
- `claims` accepts the Federal doc and rejects ICICI/HDFC/SBI/Yes text + a wrong `bank_code`;
  byte-for-byte determinism (two calls equal).

The existing core suite is green on the pinned toolchain, so the reused seam/helpers/harness are a
stable foundation. The throwaway crate was created outside the repo and removed after verification
(nothing committed).

---

## Resolved unknowns (summary)

| Unknown | Resolution |
|---|---|
| Module layout | `statement/federal.rs`, single `FederalReader` config + `enrich`, structured like `sbi.rs`/`yes.rs` (D1). |
| Single vs composite reader | Single layout → `read_lines(&FederalReader, …)` directly, like ICICI/SBI/Yes (D2). |
| Row regex + middot separator | Ported byte-for-byte; unescaped `.` matches the middot (any single char), encoding-robust; `₹` excluded from `amount`; `HH:MM` consumed (D3). |
| Row date format | Reuse `parse_date`; `%d-%m-%Y` already present (commented "Scapia/Federal") (D4). |
| Billing-cycle date format | Reuse `parse_date`; `%d%b%Y` (space-stripped) already present (commented Scapia cycle) (D5). |
| Direction | Federal-local: leading `+` → Credit, else `classify(desc, None, None)`; same in-reader pattern as HDFC monthly; NOT the shared marker path (D6). |
| `card_last4` (un-anchored) | `find_last4(full_text, None)` → `"4836"`; strict PAN needs leading digits (none), loose PAN matches the 12 X's + 4836; not confused by `x`/dates; `None` when absent (D7). |
| Amount format | Reuse `parse_amount`; exact `Decimal`, `₹`/`+`/Indian grouping stripped, scale preserved (D8). |
| FFI surface & claims | `read_federal_statement` + `federal_claims`, `BANK_CODE "FEDERAL"`, markers `("Scapia", "Federal Bank")` (D9). |
| Reconciliation carve-out | **None needed** — the web `_enrich` is already cycle + last-4 only; 1:1 port (D10). |
| New dependency / new shared helper | **None** — pure drop-in (D1, plan Constitution Check). |
