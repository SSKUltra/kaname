# Phase 0 — Research: HDFC Credit-Card Parser (second real reader, two layouts)

**Feature**: `003-hdfc-cc-parser` | **Date**: 2026-07-15
**Method**: The web engine is the source of truth. Its HDFC reader
(`finance-tracker-phase/backend/app/services/ingestion/statement_readers/hdfc.py`) was
**executed** on both the year-end characterization vector and a fabricated monthly vector to
capture ground-truth output, and the riskiest port mechanics were **verified in a throwaway
Rust build** against the workspace's pinned crates (`regex 1`, `chrono 0.4`, `rust_decimal 1`).
Every decision below is a faithful port or a justified, verified idiomatic deviation.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed
here with evidence. **Headline finding: HDFC requires no new dependency (runtime or dev).**

---

## D1 — Reuse the ICICI foundations wholesale; add HDFC as one new module

**Decision**: Add `statement/hdfc.rs` (mirroring the web `hdfc.py`) and touch nothing structural
elsewhere. HDFC **reuses**, unchanged: the `LineReaderConfig` trait + `read_lines`/`claims` seam
(`line_reader.rs`), `ParsedStatement`/`ParsedTransaction` (`base.rs`), `parse_amount`/`parse_date`
/`find_last4` (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness
(`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom
types, `Direction` enum), and the privacy-egress gate + CI. The exported FFI functions live in
`ffi.rs`, as with ICICI.

**Rationale**: The ICICI slice built these as the reuse surface for exactly this moment;
mirroring `hdfc.py → hdfc.rs` keeps the port a mechanical, reviewable diff and proves the seam
generalizes to a second bank (the slice's thesis).

**Alternatives**: Rebuild any of the shared helpers for HDFC — rejected: violates FR-020 and the
"reuse, not rebuild" assumption; risks parity drift.

---

## D2 — Composite (multi-layout) reader: a new reusable `read_lines_first_match`

**Decision**: Model HDFC as **two zero-sized configs** — `HdfcYearEndReader` and
`HdfcMonthlyReader` — each `impl LineReaderConfig`, sharing one free `enrich` function. Compose
them with a **new** generic helper in `line_reader.rs`:

```rust
pub fn read_lines_first_match(
    cfgs: &[&dyn LineReaderConfig],
    lines: &[String],
    full_text: &str,
) -> ParsedStatement {
    let mut last: Option<ParsedStatement> = None;
    for &cfg in cfgs {
        let statement = read_lines(cfg, lines, full_text);
        if !statement.lines.is_empty() {
            return statement;      // first layout that produced rows wins
        }
        last = Some(statement);    // remember the last (enriched) empty statement
    }
    last.unwrap_or_else(|| ParsedStatement::new(""))   // unreachable for a non-empty cfgs slice
}
```

This mirrors the web `HdfcCreditCardReader.read_lines` exactly ("return the first statement whose
`lines` are non-empty, else the last empty statement"). Dynamic dispatch over the heterogeneous
configs requires relaxing the existing seam to accept an unsized `C`:

```rust
pub fn read_lines<C: LineReaderConfig + ?Sized>(cfg: &C, …) -> ParsedStatement   // was `C: LineReaderConfig`
pub fn claims<C: LineReaderConfig + ?Sized>(cfg: &C, …) -> bool
```

The trait is already object-safe (no generic methods, no `Self` by value), so `&dyn
LineReaderConfig` works. HDFC calls
`read_lines_first_match(&[&HdfcYearEndReader, &HdfcMonthlyReader], lines, full_text)` (year-end
first, monthly fallback — FR-004).

**Verified**: the `&[&dyn Trait]` + `?Sized` pattern compiles and runs on the pinned crates
(scratch test `dyn_composite_pattern_compiles_and_runs`). The relaxation is **backward-compatible**
— `read_lines(&IciciReader, …)` still compiles (`IciciReader: Sized`).

**Rationale**: Keeps the composite logic in the shared subsystem for later multi-layout banks
(FR-020); mirrors the web's tuple-of-readers; no new dependency, no allocation.

**Alternatives**: Inline the loop twice in `hdfc.rs` — rejected: no reuse, drifts from the web.
An `enum Layout { YearEnd, Monthly }` — rejected: not extensible to future banks.

**Note on `enrich` + empty fallback**: each config's `read_lines` runs `enrich` even when it
matched zero rows, so the returned statement (whichever) is always enriched. For a year-end doc
the year-end config returns non-empty; for a monthly doc the year-end config returns **empty**
(monthly rows never match the year-end regex — D6) and monthly returns non-empty; for neither,
the last empty (enriched) statement is returned (US2-S4 / FR-004). `cfgs` is always non-empty in
practice, so the `unwrap_or_else` branch is unreachable (documented; keeps the helper total).

---

## D3 — Year-end row regex reproduces Python's captures (VERIFIED)

**Decision**: Port the year-end row pattern **exactly** (note: **not** anchored at end — a
trailing masked card number after the marker is ignored, per the spec edge case):

```text
^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>DR|CR)\b
```

Direction = `classify(desc, caps.name("dir"), None)` — i.e. the **existing** `polarity::classify`
via its explicit-marker path (identical to the web's `marker_direction()`), so `CR → Credit`,
`DR → Debit` (FR-011).

**Evidence** (scratch Rust run on `regex 1`, `captures()`):

| Line | date | desc | amount | dir |
|---|---|---|---|---|
| `16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070` | `16-Apr-2025` | `ONLINE TRF - PYMT RECD - THANK YOU` | `10,610.00` | `CR` |
| `04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070` | `04-Apr-2025` | `WWW EXAMPLE COM GURGAON` | `1,071.00` | `DR` |

The trailing `526873XXXXXX9070` is correctly **outside** the match (no `$` anchor). `regex` uses
leftmost-first (Perl-like) semantics, matching Python here; the seam feeds one line per
`captures()` call so `^` anchors per line. **The golden parity test is the permanent guard.**

---

## D4 — Monthly row regex + the Rupee-glyph `C` and leading `+` (VERIFIED)

**Decision**: Port the monthly row pattern **exactly**:

```text
^(?P<date>\d{2}/\d{2}/\d{4})\s*\|?\s*\d{1,2}:\d{2}\s+(?P<desc>.+?)\s+(?P<dir>\+\s*)?C\s*(?P<amount>[\d,]+\.\d{2})\b
```

Two subtleties, both ported faithfully and verified:
- The literal **`C`** (how the ₹ glyph extracts) sits **outside** the `amount` group, so
  `parse_amount` receives only the digits — the `C` is never mistaken for the amount and never
  folded into `desc` (FR-008, SC-006, US2-S2).
- A leading **`+`** is captured in the optional `dir` group. **NEW monthly-direction rule** (D5,
  **not** `classify`): `Credit` iff `dir.trim().starts_with('+')`, else `Debit` (FR-012).

**Evidence** (scratch Rust run):

| Line | date | desc | amount | dir | direction |
|---|---|---|---|---|---|
| `15/05/2026\| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00` | `15/05/2026` | `EXAMPLE MERCHANT BANGALORE` | `1,639.00` | *(none)* | Debit |
| `20/05/2026\| 09:05 CC PAYMENT RECEIVED + C 6,738.00` | `20/05/2026` | `CC PAYMENT RECEIVED` | `6,738.00` | `+ ` | Credit |

The day-first date parses as `%d/%m/%Y` (`15/05/2026 → 2026-05-15`; FR-004/US2-S3) — already in
`DATE_FORMATS` (D8). Non-greedy `desc` stops at the first ` [+ ]C <amount>`, matching Python.

---

## D5 — Monthly leading-`+` direction rule (NEW; deliberately not `classify`)

**Decision**: Implement the monthly config's `direction()` as a **small, self-contained rule**
(not `classify`), mirroring the web's `_monthly_direction()`:

```rust
fn direction(&self, caps: &Captures<'_>, _description: &str) -> Direction {
    let plus = caps.name("dir").map_or("", |m| m.as_str()).trim().starts_with('+');
    if plus { Direction::Credit } else { Direction::Debit }
}
```

**Rationale**: In the monthly layout the credit signal is *only* the leading `+` — there is no
`DR`/`CR` marker and the description language must not be consulted (a monthly "CC PAYMENT
RECEIVED" is credit **because of the `+`**, not the words). Routing it through `classify` would
wrongly let keyword/paren heuristics fire. This is the web's explicit design (a dedicated
`DirectionFn`), so faithful parity requires the dedicated rule. The **year-end** config keeps
using `classify` (D3). **Verified** by the ground-truth run (rows classify Debit/Credit purely on
the `+`).

**Placement**: kept in `hdfc.rs` (the leading-`+` convention is HDFC-specific). It reads as a
named rule so a future co-brand bank can lift it; promoting it to `polarity.rs` was considered
and deferred (no second consumer yet — avoid speculative generality).

---

## D6 — Layout ordering is safe: the two row regexes are mutually exclusive (VERIFIED)

**Risk**: Trying year-end first then monthly could mis-parse a monthly statement (or vice versa).

**Evidence** (scratch Rust run `year_end_row_does_not_match_monthly_and_vice_versa`): a year-end
row (`16-Apr-2025 …`) does **not** match the monthly regex (which needs `^\d{2}/\d{2}/\d{4}`), and
a monthly row (`15/05/2026| 13:30 …`) does **not** match the year-end regex (which needs
`^\d{2}-[A-Za-z]{3}-\d{4}`). So on a monthly statement the year-end config yields **zero** rows
and the composite falls through to monthly (FR-004); ordering never causes a mis-parse. A
statement matching neither yields an empty result with no error (US2-S4).

---

## D7 — Enrichment: reuse `find_last4` anchor + `_PERIOD_RE`/`_MONTHLY_PERIOD_RE` (VERIFIED)

**Decision**: One shared `enrich(statement, full_text)` used by **both** configs (ported from
the web `_enrich`):

1. **Year-end period** — `_PERIOD_RE = (?i)period from\s+([A-Za-z]+-\d{2})\s+to\s+([A-Za-z]+-\d{2})`:
   `period_end = month_year_end(g2)` (last day of the closing month); `period_start =
   month_year_end(g1).with_day(1)` (first day of the opening month) (FR-013).
2. **Else monthly period** — `_MONTHLY_PERIOD_RE = (?i)Billing Period\s+(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})\s*-\s*(\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4})`:
   `period_start = parse_date(g1.replace(',', ""))`, `period_end = parse_date(g2.replace(',', ""))`
   — needs `%d %b %Y`/`%d %B %Y`, **already** in `DATE_FORMATS` (FR-014).
3. **Card last-4** — `card_last4 = find_last4(full_text, Some("Card Number"))` — the **anchor**
   path already exists in `common.rs` (built for ICICI's reuse, previously untested); HDFC is its
   first consumer (FR-015).

`ParsedStatement.period_start` is **already a field** (`base.rs`) — ICICI leaves it `None`; HDFC
populates it. No record change.

**Evidence** (live web-engine run — both vectors):

| Vector | period_start | period_end | card_last4 |
|---|---|---|---|
| year-end (`period from APRIL-25 to MARCH-26`, `Card Number XXXX6873XXXXXX9070`) | `2025-04-01` | `2026-03-31` | `9070` |
| monthly (`Billing Period 15 May, 2026 - 14 Jun, 2026`, `Card Number XXXX1234XXXXXX5678`) | `2026-05-15` | `2026-06-14` | `5678` |

Missing metadata → left `None`, transactions still returned (FR-016, US4-S4).

---

## D8 — Dates: no new formats needed (VERIFIED)

**Decision**: Reuse `parse_date`/`DATE_FORMATS` unchanged. HDFC exercises three already-present
formats: `%d-%b-%Y` (year-end rows, `16-Apr-2025`), `%d/%m/%Y` (monthly rows, `15/05/2026`), and
`%d %b %Y` (monthly billing period, `15 May 2026` after comma removal). `chrono`'s `%b`/`%B` use
built-in English month tables → locale-independent/deterministic (FR-019).

**Evidence**: the `common.rs` `DATE_FORMATS` list already contains all three (see lines 20–33);
the ground-truth run parsed every HDFC date correctly.

---

## D9 — `month_year_end`: NEW shared date helper (VERIFIED)

**Decision**: Add to `common.rs` (the shared helpers home, beside `parse_date`), per FR-020:

```rust
pub fn month_year_end(token: &str) -> Option<NaiveDate> {
    // token like "MARCH-26": name (first 3 letters, case-insensitive) + 2-digit year.
    // month via a JAN..DEC table; year = 2000 + yy; day = last day of that month
    // (first day of next month minus one), computed via chrono. Invalid → None.
}
```

Ported from the web's module-private `_month_year_end` + `_MONTHS`. Placed in `common.rs` (not
`hdfc.rs`) so later year-end statements from other banks reuse it — the requester's explicit
"add to the shared reader subsystem" directive.

**Evidence** (scratch Rust run `month_year_end_and_start`): `MARCH-26 → 2026-03-31`,
`APRIL-25 → 2025-04-30` (⇒ `period_start` via `.with_day(1)` = `2025-04-01`), leap
`FEB-24 → 2024-02-29`, December wrap `DEC-25 → 2025-12-31`, invalid `BOGUS-99 → None`.

**Alternatives**: keep it module-private in `hdfc.rs` (mirrors the web file layout) — deferred to
the reuse directive; documented as a deliberate placement choice (sanity-check item S2 below).

---

## D10 — Golden vectors + the one minimal harness delta (`period_start`)

**Decision**: Two fixtures under `fixtures/hdfc/credit_card/`:

- **`year_end.json`** — **ported** from the web characterization vector (`_HDFC_LINES` /
  `_HDFC_TEXT`, `test_cc_reader_characterization.py`). `expected` captured from the live reader.
- **`monthly.json`** — **fabricated** (synthetic merchant/amount/masked PAN); `expected`
  **captured from a live `hdfc.reader.read_lines(...)` run**, never hand-derived (FR-026).

Both are registered as **two new case-table rows** in `tests/parity.rs`, **both calling
`read_hdfc_statement`** (the composite) — proving the caller never selects a layout (SC-004).

**Harness delta (the one code change beyond rows)**: add `#[serde(default)] period_start:
Option<String>` to `Expected` and one assertion (`statement.period_start == want_period_start`).
Necessary because HDFC is the first reader to populate `period_start` and SC-003/US6-AC1 require
parity to pin it. **Backward-compatible**: ICICI's fixture omits the key → `None`, and ICICI's
`period_start` is already `None`. (See Complexity Tracking.)

**Ground truth captured** (both vectors, from a live web-engine run — `description_raw` is
asserted **byte-for-byte**, so these exact strings are the parity anchor):

*year_end.json* — `lines`:
1. `16-Apr-2025 ONLINE TRF - PYMT RECD - THANK YOU 10,610.00 CR 526873XXXXXX9070`
2. `04-Apr-2025 WWW EXAMPLE COM GURGAON 1,071.00 DR 526873XXXXXX9070`

`full_text` contains `HDFC Bank Credit Cards`, `Account Summary for the period from APRIL-25 to
MARCH-26`, `Card Number XXXX6873XXXXXX9070`, then the two lines. `expected.rows`:
1. `{ 2025-04-16, "10610.00", Credit, INR, "ONLINE TRF - PYMT RECD - THANK YOU" }`
2. `{ 2025-04-04, "1071.00", Debit, INR, "WWW EXAMPLE COM GURGAON" }`
`period_start "2025-04-01"`, `period_end "2026-03-31"`, `card_last4 "9070"`, `errored_lines []`.

*monthly.json* — `lines`:
1. `15/05/2026| 13:30 EXAMPLE MERCHANT BANGALORE C 1,639.00`
2. `20/05/2026| 09:05 CC PAYMENT RECEIVED + C 6,738.00`

`full_text` contains `HDFC Bank Credit Card`, `Billing Period 15 May, 2026 - 14 Jun, 2026`,
`Card Number XXXX1234XXXXXX5678`, then the two lines. `expected.rows`:
1. `{ 2026-05-15, "1639.00", Debit, INR, "EXAMPLE MERCHANT BANGALORE" }`
2. `{ 2026-05-20, "6738.00", Credit, INR, "CC PAYMENT RECEIVED" }`
`period_start "2026-05-15"`, `period_end "2026-06-14"`, `card_last4 "5678"`, `errored_lines []`.

> **/speckit.tasks + /speckit.implement MUST** re-capture `monthly.json`'s `expected` by running
> the web reader (the values above are the captured ground truth to reproduce, recorded here so
> the plan is concrete; the implementer confirms them with a live run, not by hand).

---

## D11 — UniFFI exposure: two functions, reuse the ICICI bridge (no `uniffi.toml` change)

**Decision**: Add to `ffi.rs`, reusing the P1/ICICI custom types + `Direction` unchanged:

```rust
#[uniffi::export] pub fn read_hdfc_statement(lines: Vec<String>, full_text: String) -> ParsedStatement;
#[uniffi::export] pub fn hdfc_claims(full_text: String) -> bool;   // claims(&HdfcYearEndReader, &full_text, "HDFC")
```

`read_hdfc_statement` wraps `read_lines_first_match(&[&HdfcYearEndReader, &HdfcMonthlyReader], …)`;
`hdfc_claims` delegates to the **year-end** config's `claims` (both configs share the markers), so
an ICICI document is not claimed (FR-002). `lib.rs` re-exports both. **No record and no
`uniffi.toml` change** (no new record; `ParsedStatement`/`ParsedTransaction` already `uniffi::Record`).

**Rationale**: purely additive to the bindings; mirrors the ICICI recognition/parse split; keeps
"boundary in one file".

---

## D12 — Privacy-egress: inherited, and provably unchanged (no new dependency)

**Decision**: HDFC adds **no** dependency (runtime or dev), so `kaname-core`'s shipped
`cargo tree -e normal` graph is byte-identical and `make core-privacy-audit` passes unchanged
(FR-022/024). The determinism/purity parity guard extends to the two HDFC vectors (identical
output across repeated calls — SC-008/009). No telemetry/analytics/crash reporter enters the
parse path (FR-023). The audit + CI wiring from the ICICI slice covers HDFC with **zero** new
config.

**Confirmation**: the design uses only `regex`, `rust_decimal`, `chrono`, `serde` (runtime) and
`serde_json` (dev, harness) — all already in the graph. No `reqwest`/`hyper`/`tokio`/`rustls`/…
anywhere. (Re-run `make core-privacy-audit` in implementation to confirm the `OK` line.)

---

## D13 — Build/verify ordering & local simulator (reuse the gate unchanged)

**Decision**: No change to gate mechanics (FR-030). `make core-xcframework` **precedes**
`tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first) — the
two new exports are rebuilt into the bindings there. CI's iOS job stays on **`macos-15`**; the
`xcodebuild` destination is the **iPhone 16** simulator (`OS=latest`); the core (ubuntu) job's
privacy audit is inherited. Local Xcode requires an explicitly-created **iPhone 16** simulator
for `make ios-test`.

---

## Sanity-check items (surface to the requester)

- **S1 — `period_start` harness field**: adding `period_start` to the parity `Expected` is the
  single harness code change beyond the two case rows. It is minimal and backward-compatible
  (ICICI untouched). *Recommended* (parity must pin `period_start` — SC-003). Flagged because the
  brief said "avoid harness code changes beyond [fixtures + rows]".
- **S2 — `month_year_end` placement**: placed in `common.rs` (shared/reusable) rather than
  module-private in `hdfc.rs` (the web's layout), honoring the "add to the shared reader
  subsystem so later multi-layout banks reuse" directive. Easy to move to `hdfc.rs` if strict
  file-layout parity is preferred.
- **S3 — Monthly direction rule**: implemented as an HDFC-local rule (not `classify`), matching
  the web's dedicated `DirectionFn`. Kept in `hdfc.rs` (no second consumer yet).
- **S4 — Monthly fixture values**: fabricated (`EXAMPLE MERCHANT BANGALORE`, `CC PAYMENT
  RECEIVED`, PAN `…5678`, `2026-05` dates). Confirm the synthetic choices are acceptable; the
  `expected` is captured from the live web reader, so any change to the fabricated `lines`/text
  must be re-captured (never hand-edited).

---

## Resolved unknowns summary

| Unknown | Resolution |
|---|---|
| How to model two layouts behind one reader? | Two configs + new `read_lines_first_match(&[&dyn LineReaderConfig], …)`; year-end first, monthly fallback (D2). |
| Do the two HDFC regexes match Python's captures? | Yes — verified byte-for-byte, incl. ignored trailing card number and the `C`/`+` handling (D3, D4). |
| Is year-end-first ordering safe? | Yes — the two row regexes are mutually exclusive (D6, verified). |
| Monthly direction? | Leading-`+` rule, **not** `classify` (D5). |
| Exact `description_raw` (asserted byte-for-byte)? | Captured from the live reader: year-end `"ONLINE TRF - PYMT RECD - THANK YOU"` / `"WWW EXAMPLE COM GURGAON"`; monthly `"EXAMPLE MERCHANT BANGALORE"` / `"CC PAYMENT RECEIVED"` (D10). |
| `period_start`/`period_end` derivation? | Year-end via `month_year_end` (new helper, verified); monthly via `parse_date` on the Billing Period (D7, D9). |
| New date formats? | None — `%d-%b-%Y`, `%d/%m/%Y`, `%d %b %Y` already in `DATE_FORMATS` (D8). |
| Card last-4? | `find_last4(full_text, Some("Card Number"))` — the existing anchor path (D7). |
| New dependencies? | **None** — runtime *or* dev (D12). |
| Harness change? | Two case rows + one backward-compatible `period_start` field (D10). |
