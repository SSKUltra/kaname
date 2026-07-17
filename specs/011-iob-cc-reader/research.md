# Phase 0 — Research: Indian Overseas Bank (IOB) Credit-Card Parser (sixth & final CC reader, single layout, zero new infra)

**Feature**: `011-iob-cc-reader` | **Date**: 2026-07-17
**Method**: The web engine is the source of truth. Its IOB reader
(`finance-tracker-phase/backend/app/services/ingestion/statement_readers/iob.py`) was **read as ground
truth**, and the two IOB-specific behaviours (uppercase-month `%b` parsing; the inline masked-PAN
`find_last4`) were **verified by running the real `kaname-core` helpers** (a throwaway integration test
path-depending on `kaname-core`, on the pinned stable toolchain, removed after use). Every decision
below is a faithful port or a justified, verified idiomatic mapping.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed here with
evidence. **Headline finding: IOB requires no new dependency and no new shared helper — it is a third
clean single-layout drop-in after SBI and Yes, reusing everything the earlier slices built. The only
non-mechanical decisions are the reconciliation carve-out (D10, mirroring Yes) and the deliberately
absent `period_start` (D6). Landing IOB completes the full 10-reader set (6 CC + 4 bank).**

---

## D1 — Reuse the landed foundations wholesale; add IOB as one new module, structured like `yes.rs`

**Decision**: Add `statement/iob.rs` (mirroring the web `iob.py`) and touch nothing structural
elsewhere. IOB **reuses, unchanged**: the `LineReaderConfig` trait + `read_lines`/`claims` seam
(`line_reader.rs`), `ParsedStatement`/`ParsedTransaction` (`base.rs`), `parse_amount`/`parse_date`/
`find_last4` (`common.rs`), `polarity::classify` (`polarity.rs`), the parity harness
(`tests/parity.rs`), the UniFFI bridge (`ffi.rs` + `uniffi.toml`: `Decimal`/`NaiveDate` custom types,
`Direction` enum), and the privacy-egress gate + CI. It is structured **identically to `yes.rs`**: a
single zero-sized `IobReader` config + a free `enrich`, with a module comment recording the
reconciliation carve-out. Exported FFI functions live in `ffi.rs`, as with SBI/Yes/Federal.

**Rationale**: The ICICI slice built this reuse surface; HDFC proved it generalizes to multi-layout;
SBI and Yes proved a clean single-layout bank is a tiny, repeatable step. IOB is the third such
drop-in (and the sixth and final credit-card bank); mirroring `iob.py → iob.rs` keeps the port a
mechanical, reviewable diff and closes out the credit-card reader set.

**Alternatives**: Rebuild any shared helper for IOB — rejected: violates FR-019 and the "reuse, not
rebuild" assumption; risks parity drift.

---

## D2 — Single-layout reader: use `read_lines` directly (NOT the composite)

**Decision**: IOB has exactly **one** row layout, so `read_iob_statement` wraps
`read_lines(&IobReader, lines, full_text)` **directly** — exactly like `read_yes_statement` and
`read_sbi_statement`. It does **not** use HDFC's `read_lines_first_match` composite (that helper exists
for multi-layout banks and is simply not needed here).

**Rationale**: The web `iob.py` builds a single `LineStatementReader` with one `_ROW_RE`. Wrapping the
single config directly is the faithful, minimal mapping.

**Alternatives**: Route IOB through `read_lines_first_match(&[&IobReader], …)` — rejected: needless
indirection for a single layout; SBI/Yes's direct pattern is the precedent.

---

## D3 — Row regex ported byte-for-byte; terminal `Dr`/`Cr` marker anchored at `$`

**Decision**: Port `_ROW_RE` verbatim into a `LazyLock<Regex>`:

```text
^(?P<date>\d{2}-[A-Za-z]{3}-\d{4})\s+(?P<desc>.+?)\s+(?P<amount>[\d,]+\.\d{2})\s+(?P<dir>Dr|Cr)$
```

Named groups `date`/`desc`/`amount` match the seam's default group names; `dir` is the terminal
two-letter marker. The `read_lines` seam calls `row_re.captures(line)`; with `^…$` anchoring this is
equivalent to the web's `re.match` on a single line. The date sub-pattern is `\d{2}-[A-Za-z]{3}-\d{4}`
— a two-digit day, a **case-insensitive** three-letter month (`[A-Za-z]{3}` accepts uppercase `MAR`,
`APR`), and a four-digit year — the only structural difference from the Yes/SBI row regexes.

**Traced against the golden lines**:
- `31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr` → `date="31-MAR-2026"`, `desc="ExampleRefundMerchant"`,
  `amount="1,000.00"`, `dir="Cr"`.
- `04-APR-2026 ExampleStorePurchase 3,500.00 Dr` → `desc="ExampleStorePurchase"`, `amount="3,500.00"`,
  `dir="Dr"`.
- Non-transaction lines have no leading `DD-MON-YYYY` date + trailing `Dr`/`Cr` and are skipped: the
  header, `Credit Card Number …`, `123456XXXXXX0042 16000 25091.5`, `ACCOUNT SUMMARY`, the summary
  values row `345.50 1,000.00 3,500.00 0 2,845.50`, `Total Purchase : 2845.50`, and the
  `*********** End of Statement ***********` marker (FR-005, SC-007). None matches → 0 spurious rows,
  0 errored lines.

**Rationale/Alternatives**: The pattern is simple and anchored; no idiomatic deviation is needed. Rust
`regex` behaves identically to Python's `re` for this pattern (no backreferences/lookaround used).

---

## D4 — Date: `DD-MON-YYYY` with an UPPERCASE month parses via the ALREADY-PRESENT `%d-%b-%Y` (no new date code) — **VERIFIED**

**Decision**: Parse dates with the existing `common::parse_date`. The `%d-%b-%Y` format is **already**
present (`common.rs:28`, commented `// 04-Apr-2025 (HDFC)`), and **`chrono`'s `%b` month table is
case-insensitive**, so an uppercase month token parses with no IOB-specific date code. `chrono`'s
`%b`/`%B` use built-in English month tables and are locale-independent (determinism).

**Verified against the real crate** (throwaway integration test on the pinned toolchain):
`parse_date("31-MAR-2026") = 2026-03-31`, `parse_date("04-APR-2026") = 2026-04-04`,
`parse_date("20-APR-2026") = 2026-04-20`. No IOB-specific date code (FR-003, SC-001, US2-AC1;
edge case "Uppercase month in the date"). This directly de-risks the requester's sanity-check on
uppercase-month `%b` parsing.

**Alternatives**: A dedicated IOB date parse or a `.to_titlecase()` pre-normalisation — rejected: the
shared parser already covers uppercase months; adding code would violate "no new shared helper".

---

## D5 — Direction: two-letter `Dr`/`Cr` markers are ALREADY handled by `polarity::classify`

**Decision**: `direction(caps, desc) = classify(desc, caps.name("dir").map(str), None)` — identical to
`yes.rs`/`sbi.rs`, and the exact behaviour of the web's `marker_direction()`
(`polarity.classify(description, dr_cr_marker=match.group("dir"))`). No IOB-specific direction code.

**Why it already works**: `normalise_marker` filters to alphabetic/dash chars, upper-cases, and checks
the shared tables — `"Dr" → "DR"` (∈ `DR_MARKERS`), `"Cr" → "CR"` (∈ `CR_MARKERS`)
(`polarity.rs:11–12`). The explicit marker wins **before** any description-keyword check, so a
`Dr`/`Cr` marker always decides direction (FR-008/009, SC-005).

**Traced/known-good**: `Cr → Credit`, `Dr → Debit`. Direction is independent of amount magnitude — the
`Cr` refund of `1000.00` is **credit** while the larger `Dr` purchase of `3500.00` is **debit**
(US3-AC4, edge case "Direction independent of magnitude"). A description containing a credit/debit-like
word does not override the terminal marker (US3-AC3) — this is the same guarantee the `polarity`
`explicit_marker_wins` unit test already asserts. Amount value/sign is never consulted (FR-008).

**Alternatives**: A bespoke `Dr`/`Cr` rule — rejected: unnecessary; the shared classifier already maps
`Dr`/`Cr`. This is the same reuse SBI (`C`/`D`) and Yes (`Dr`/`Cr`) demonstrated.

---

## D6 — Enrichment: billing-cycle END from the lone `Stmt Date`; NO `period_start`; last-4 via the `Credit Card Number` anchor

**Decision**: Port the enrichment faithfully into a free `enrich(statement, full_text)` — **the
`period_end` + last-4 parts only** (the printed-total scrape is dropped; see D10). Crucially, IOB sets
**only** `period_end` (there is no printed period range):

```text
STMT_DATE_RE = (?i)Stmt Date\s*:\s*(\d{2}-[A-Za-z]{3}-\d{4})
  → if it matches: statement.period_end = parse_date(g1)     // period_start stays None (default)
statement.card_last4 = find_last4(full_text, Some("Credit Card Number"))
```

`period_start` is a `ParsedStatement` field (added by HDFC) that **remains at its `None` default** —
IOB never assigns it. The `STMT_DATE_RE` is case-insensitive (`(?i)`) and tolerant of spacing around
the colon (`\s*:\s*`), matching `iob.py`'s `re.IGNORECASE` `_STMT_DATE_RE` (FR-010, US4-AC3). This is
the notable structural difference from `yes.rs`/`sbi.rs`, whose `enrich` sets **both** ends from a
`<from> to <to>` range.

**Traced** (SC-003):
- `Stmt No: 2026CC0000001 Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in` → `STMT_DATE_RE`
  matches `Stmt Date: 20-APR-2026` (the earlier `Stmt No:` is not `Stmt Date`, so the search skips it),
  captures `20-APR-2026` → `period_end = 2026-04-20`; `period_start` left `None`.
- `Credit Card Number …` + inline `123456XXXXXX0042 …` → `card_last4 = "0042"` (see D7).
- Missing metadata → fields left `None`, transactions still returned (FR-012, US4-AC4).

**Alternatives**: Fabricate a `period_start` (e.g. `period_end − 1 month`) — rejected: invents data the
statement does not print (determinism/faithfulness); `iob.py` sets only `period_end`.

---

## D7 — Why `card_last4` is `"0042"` for the INLINE masked PAN, with NO bleed from the limit figures — **VERIFIED**

**Decision/Finding**: `find_last4(full_text, Some("Credit Card Number"))` returns **`"0042"`** — the
trailing four of the masked PAN `123456XXXXXX0042` — and **never** digits from the adjacent limit
figures `16000` / `25091.5` printed on the same line. This falls out of the existing `find_last4_in`
regexes with **no IOB-specific code**:

- The anchor pass keeps lines containing `credit card number` (case-insensitive). In this statement the
  anchor text (`Credit Card Number Cash Limit (as part of credit limit) Available Credit Limit`) is a
  **header row that carries no PAN**; the masked PAN is on the *next* line
  (`123456XXXXXX0042 16000 25091.5`). So the anchored pass finds nothing and `find_last4` **falls back
  to the whole document** (`common.rs:149–164`) — this is the intended fallback behaviour, not a
  workaround.
- On the whole text, `STRICT_PAN_RE = [0-9]{2,6}[Xx*]{2,}[0-9]{4}` matches **only** `123456XXXXXX0042`
  (`123456` leading digits, `XXXXXX` mask run, `0042` four trailing digits). The manual neighbour
  checks (`common.rs:117–129`, compensating for Rust `regex`'s lack of lookaround) pass — the char
  before the match is a newline and the char after is a space, neither a PAN char — so the strict match
  is accepted → last-4 `"0042"`. The limit tokens `16000` and `25091.5` contain **no mask char**, so
  they can never match `STRICT_PAN_RE`, and the strict match is returned **before** any looser pass.

**Verified against the real crate** (throwaway integration test on the pinned toolchain, using the
exact fixture `full_text`): `find_last4(full_text, Some("Credit Card Number")) = "0042"` — **not**
`6000`, `5091`, or any digits from the adjacent limits (FR-011, SC-004, US4-AC2; edge case "Card last-4
from an inline masked card number"). This directly de-risks the requester's sanity-check. Matches the
web engine's `last4 = "0042"`.

**Note on the anchor**: passing `Some("Credit Card Number")` is a faithful port of `iob.py`
(`anchor="Credit Card Number"`). Here the anchor line holds no PAN, so the anchor does not narrow the
search, but including it is correct (it matches the source and would help on statements where the PAN
shares the anchor line). The whole-text fallback is what recovers `"0042"`.

---

## D8 — Amounts: exact `Decimal`, Indian grouping, scale preserved (reused `parse_amount`)

**Decision**: Amounts parse via the existing `common::parse_amount` → `rust_decimal::Decimal`, never
`f64`. Thousands separators (incl. the Indian `1,23,456` grouping) are stripped; scale is preserved.

**Known-good** (existing `common.rs` unit tests): `1,000.00 → 1000.00` and `3,500.00 → 3500.00` (2dp
kept); Indian grouping `1,23,456.78 → 123456.78`. Amounts are non-negative; direction is carried
separately (FR-006/007, SC-006).

---

## D9 — Claims / issuer plausibility; two FFI exports mirroring SBI/Yes/Federal

**Decision**: `BANK_CODE = "IOB"`; `claim_markers = ("INDIAN OVERSEAS BANK", "iobnet.co.in")` (**two**
markers, faithful to `iob.py`). `iob_claims(full_text)` delegates to `claims(&IobReader, full_text,
"IOB")`; `read_iob_statement` wraps `read_lines(&IobReader, lines, full_text)`. Both are
`#[uniffi::export]` in `ffi.rs` and re-exported from `lib.rs`, mirroring the SBI/Yes/Federal surface
(FR-020). `claims` lower-cases the haystack and matches either marker case-insensitively
(`line_reader.rs:40–43`), so `INDIAN OVERSEAS BANK` (in the header) and `iobnet.co.in` (in the e-mail
line) both qualify.

**Traced**: `iob_claims` claims its own doc (contains `INDIAN OVERSEAS BANK` and `iobnet.co.in`);
rejects `ICICI Bank Statement` and other issuers' text; and the `bank_code` gate rejects a non-`IOB`
code even on IOB text (FR-002, SC-002). The parity harness adds an
`iob_claims_accepts_own_document_and_rejects_others` test mirroring the sbi/yes/federal claims tests.

---

## D10 — Reconciliation carve-out: DO NOT port the `ACCOUNT SUMMARY` printed-total scrape (mirrors Yes)

**Decision**: **Do not port** the web `_enrich`'s printed per-statement debit/credit totals. The web
`iob.py` additionally runs:

```python
_SUMMARY_RE = ACCOUNT SUMMARY\b.*?(?P<prev>…)\s+(?P<credits>[\d,]+\.\d{2})\s+(?P<debits>[\d,]+\.\d{2})\s+…
# → statement.printed_total_credits = _common.parse_amount(summary.group("credits"))
#   statement.printed_total_debits  = _common.parse_amount(summary.group("debits"))
```

That regex and the `printed_total_*` assignments are **out of scope** for this slice and MUST NOT
appear in `statement/iob.rs`. The Rust `ParsedStatement` (`base.rs`) has **no** `printed_total_*`
fields — its doc-comment explicitly states the reconciliation `printed_*` totals "arrive with a later
slice." The IOB `enrich` here is therefore **only** `period_end` + last-4.

**Rationale**: This keeps IOB identically shaped to the five landed credit-card readers (none expose
printed totals), avoids shipping a **half-built reconciliation surface** with no consumer, and draws a
clean boundary for the dedicated reconciliation slice (spec Out of Scope). It is a deliberate scope
*reduction*, not a constitution violation (FR-013, US5, SC-013). This is the **same carve-out already
applied to Yes** (`005`, D10 there) — IOB follows the precedent exactly.

**Traced**: the fixture `full_text` **does** contain the `ACCOUNT SUMMARY` block and its values row
`345.50 1,000.00 3,500.00 0 2,845.50` (which `_SUMMARY_RE` would scrape into `credits=1,000.00`,
`debits=3,500.00`). Because `IobReader::enrich` never runs that regex and `ParsedStatement` has no such
fields, the parse returns **only** the two rows + `period_end 2026-04-20` + `card_last4 "0042"` — no
printed totals anywhere. The summary values row also fails `_ROW_RE` (no leading date), so it produces
neither a transaction nor an errored line.

**Alternatives**: Port the totals now (naïve faithfulness) — rejected: adds fields no landed reader
uses and ships a dangling reconciliation surface. Reconciliation is a later slice; the totals belong
there.

---

## D11 — Documentation correction is in scope: move IOB to the credit-card list in both roadmap docs

**Decision**: Correct the IOB miscategorization in the two roadmap documents (US6, FR-014/015, SC-014).
IOB is a **credit-card** reader (line-based `LineStatementReader`, registered under
`account_kind="credit_card"`, with **no** bank-account/ledger reader), yet both docs currently list it
under bank-account readers. The edits:

- **`docs/HANDOFF.md`** — credit-card list (currently
  `` `icici.py`, `hdfc.py`, `sbi_card.py`, `yes_kiwi.py`, `federal_scapia.py`. ``) gains `` `iob.py` ``;
  the bank-account list (currently ends `` … `federal_bank.py`, `au_bank.py`, `iob.py`. ``) drops
  `` `iob.py` `` → ends `` … `federal_bank.py`, `au_bank.py`. ``.
- **`docs/kaname-ios-plan.md`** — credit-card bullet (currently
  `` `icici`, `hdfc`, `sbi_card`, `yes_kiwi`, `federal_scapia`. ``) gains `` `iob` ``; the bank-account
  bullet (currently ends `` … `federal_bank`, `au_bank`, `iob`. ``) drops `` `iob` `` → ends
  `` … `federal_bank`, `au_bank`. ``.

**Rationale**: The docs are the shared map of the ingestion architecture; leaving IOB miscategorized
would imply a non-existent IOB ledger reader and misrepresent the final reader set. After the edit both
files consistently read **six credit-card + four bank-account** readers (ten total). Doc-only — no
build/test impact (verifiable by inspecting both files).

**Alternatives**: Defer the doc fix — rejected: the spec makes it an explicit deliverable of this slice
(US6), and it is the natural moment to correct it (as IOB lands as a credit-card reader).

---

## Verification harness (evidence)

A throwaway integration test (`core/crates/kaname-core/tests/tmp_iob_verify.rs`) path-depending on the
**real** `kaname-core` exercised the two IOB-specific helper behaviours over the exact fixture
`full_text`, and **both passed** on the pinned stable toolchain (`cargo 1.96.1`):

- **Uppercase-month `%b` parsing** (D4): `parse_date("31-MAR-2026") = 2026-03-31`,
  `parse_date("04-APR-2026") = 2026-04-04`, `parse_date("20-APR-2026") = 2026-04-20`.
- **Inline masked-PAN last-4, no bleed** (D7): `find_last4(full_text, Some("Credit Card Number")) =
  "0042"` — not `6000`/`5091` from the adjacent limits `16000 25091.5`.

The existing core suite is green on the pinned toolchain (`cargo test --all --all-features`: **60 unit
tests + 12 parity/integration tests pass**), so the reused seam/helpers/harness are a stable
foundation. The throwaway test was **removed after verification** (nothing committed; `git status`
clean apart from the plan artifacts). The full `IobReader` behaviour (rows, direction, `enrich`,
claims) is proven end-to-end by the golden parity `Case` row + claims test in `/speckit.implement`
(test-first).

---

## Resolved unknowns (summary)

| Unknown | Resolution |
|---|---|
| Module layout | `statement/iob.rs`, single `IobReader` config + free `enrich`, structured like `yes.rs` (D1). |
| Single vs composite reader | Single layout → `read_lines(&IobReader, …)` directly, like SBI/Yes (D2). |
| Row regex | Ported byte-for-byte; `\d{2}-[A-Za-z]{3}-\d{4}` date; terminal `Dr`/`Cr` anchored at `$` (D3). |
| Uppercase-month date | Reuse `parse_date`; `%d-%b-%Y` already present; `chrono` `%b` is **case-insensitive** — **verified** `31-MAR-2026 → 2026-03-31` (D4). |
| Direction | Reuse `classify(desc, dir, None)`; `Dr`/`Cr` already normalise to `DR`/`CR` in the polarity tables (D5). |
| Billing-cycle end / period_start | `STMT_DATE_RE` (`(?i)Stmt Date\s*:\s*<date>`) → `period_end` only; **`period_start` left `None`** (no range printed) (D6). |
| Card last-4 (inline PAN) | `find_last4(_, Some("Credit Card Number"))` → **`"0042"`**, no bleed from `16000/25091.5` — **verified** (D7). |
| Amount format | Reuse `parse_amount`; exact `Decimal`, Indian grouping, scale preserved (D8). |
| FFI surface & claims | `read_iob_statement` + `iob_claims`, `BANK_CODE "IOB"`, markers `("INDIAN OVERSEAS BANK","iobnet.co.in")` (D9). |
| Printed-total reconciliation fields | **Not ported** — out of scope, deliberate reduction; `ParsedStatement` has no such fields (D10, FR-013; mirrors Yes). |
| Roadmap-doc correction | Move IOB to the CC list, remove from the bank-account list, in `HANDOFF.md` + `kaname-ios-plan.md` (D11, FR-014/015). |
| New dependency / new shared helper | **None** — pure drop-in (D1, plan Constitution Check). |
