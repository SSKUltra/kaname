# Phase 0 — Research: ICICI Credit-Card Parser (first real reader)

**Feature**: `002-icici-cc-parser` | **Date**: 2026-07-08
**Method**: The web engine is the source of truth. It was **executed** on the synthetic ICICI
vector to capture ground-truth output, and the riskiest port mechanics were **verified in a
throwaway Rust build** against the workspace's pinned crate versions (`regex 1.12`,
`rust_decimal 1.42`, `chrono 0.4`). Every decision below is either a faithful port or a
justified, verified idiomatic deviation.

All NEEDS CLARIFICATION are resolved; the approach was locked by the requester and confirmed
here with evidence.

---

## D1 — Module layout mirrors the web engine

**Decision**: Add a `statement/` module to `kaname-core` whose files map 1:1 to the web
engine: `common.rs` ← `_common.py`, `polarity.rs` ← `polarity.py`, `line_reader.rs` ←
`_line_reader.py`, `base.rs` ← `base.py`, `icici.rs` ← `icici.py`. The two new records live in
`base.rs`; the exported FFI functions live in `ffi.rs` (the P1 boundary module).

**Rationale**: A 1:1 mapping makes every future porting slice (HDFC, SBI, Yes, Federal, bank
ledger) a mechanical, reviewable diff against its Python source and keeps the pure reader
logic free of FFI concerns (unit-testable without the bridge).

**Alternatives**: Flatten everything into `ffi.rs`/`model.rs` — rejected: poor cohesion,
harder parity review, no clean reuse seam for later readers.

---

## D2 — Reusable line reader: a `LineReaderConfig` trait, not boxed callbacks

**Decision**: Port `LineStatementReader` as a generic seam:

```rust
pub trait LineReaderConfig {
    fn bank_code(&self) -> &str;
    fn claim_markers(&self) -> &[&str];
    fn row_re(&self) -> &Regex;
    fn direction(&self, caps: &regex::Captures<'_>, description: &str) -> Direction;
    fn enrich(&self, _statement: &mut ParsedStatement, _full_text: &str) {} // default no-op
    // group names default to "date"/"desc"/"amount":
    fn date_group(&self) -> &str { "date" }
    fn desc_group(&self) -> &str { "desc" }
    fn amount_group(&self) -> &str { "amount" }
}

pub fn read_lines<C: LineReaderConfig>(cfg: &C, lines: &[String], full_text: &str) -> ParsedStatement;
pub fn claims<C: LineReaderConfig>(cfg: &C, text: &str, bank_code: &str) -> bool;
```

Each issuer is a zero-sized struct implementing the trait (`IciciReader`). The web engine's
`direction_fn`/`enrich_fn` callbacks and `marker_direction("dir")` become the `direction`/
`enrich` methods.

**Rationale**: Idiomatic, zero-cost, `Send + Sync`, trivially reusable per issuer (FR-017),
and avoids `Box<dyn Fn>` lifetime/threading friction — same shape as Python, safer in Rust.

**Alternatives**: Struct holding `Box<dyn Fn>` callbacks (literal Python port) — rejected:
heavier, needless allocation/indirection, awkward `Send + Sync` bounds.

**`read_lines` behavior (ported exactly)**: for each line, `row_re.captures(line)`; if no
match, skip (non-transaction lines ignored — FR-005); else `parse_date(date_group)` +
`parse_amount(amount_group)`; if **either is None**, push `truncate(line, 240)` to
`errored_lines` and continue (FR-014 — never panic, never drop); else build a
`ParsedTransaction { value_date, amount, direction: cfg.direction(&caps, desc),
currency: "INR", description_raw: truncate(desc.trim(), 240), bank_code }`. After the loop,
`cfg.enrich(&mut statement, full_text)`.

---

## D3 — Rust `regex` reproduces Python's lazy captures (VERIFIED)

**Risk**: The ICICI row regex uses a lazy group and an optional interior group:
`^(?P<date>\d{2}/\d{2}/\d{4})\d*\s+(?P<desc>.+?)(?:\s+\d+)?\s+(?P<amount>[\d,]+\.\d{2})(?:\s+(?P<dir>CR))?$`.
Would Rust's automaton engine capture the same spans as Python's backtracker?

**Decision/Evidence**: **Yes — verified byte-for-byte.** Running the identical pattern via
`regex 1.12` `captures()` on the two golden lines produced exactly the Python spans:

| Line | date | desc | amount | dir |
|---|---|---|---|---|
| `29/04/2026 4262 BBPS Payment received 0 13,628.36 CR` | `29/04/2026` | `4262 BBPS Payment received` | `13,628.36` | `CR` |
| `26/05/2026 1814 Fee on gaming transaction 0 10.20` | `26/05/2026` | `1814 Fee on gaming transaction` | `10.20` | *(none)* |

The `regex` crate uses leftmost-first (Perl-like) semantics, matching Python here. Anchors
`^`/`$` operate per input string; the seam feeds one line per `captures()` call, so no
multiline flag is needed. **The golden parity test is the permanent guard** against any
future divergence.

---

## D4 — `description_raw` INCLUDES the leading serial (KEY parity finding)

**Finding**: For these synthetic lines the serial (`4262`, `1814`) is **space-separated** from
the date, so the `\d*` immediately after `date` (which only eats digits *glued* to the date)
matches empty, and the serial falls into `desc`. Running the **actual web-engine reader**
(`icici.reader.read_lines(...)`) confirms `description_raw` is:

- Row 0 → **`"4262 BBPS Payment received"`**
- Row 1 → **`"1814 Fee on gaming transaction"`**

i.e. **not** `"BBPS Payment received"`. The characterization test does **not** assert on
description at all, so the true parity anchor is whatever the engine emits.

**Decision**: The golden fixture encodes the **actual web-engine output** (serial included).
Porting anything else would be a *divergence* from the source of truth. ⚠️ **Sanity-check
item** for the requester (the prompt's expected desc omitted the serial): if serial-stripping
is desired, it must first change in the web engine (then re-port), or be documented as an
intentional Kaname-only divergence with its own fixture — **not** silently introduced here.

---

## D5 — Amount parsing: `Decimal::from_str`, scale preserved, never float (VERIFIED)

**Decision**: Port `parse_amount` as: regex
`(?i)-?\(?\s*(?:₹|rs\.?|inr)?\s*([\d,]+\.\d{2})\s*\)?` → take group 1 → `replace(',', "")` →
`rust_decimal::Decimal::from_str`. Returns `Option<Decimal>` (None on no match / parse error).
Non-negative by construction (sign/parens stripped; polarity is separate — FR-006/008).

**Evidence** (scratch Rust run): `10.20 → 10.20` (scale 2 **preserved**), `13,628.36 →
13628.36`, Indian grouping `Rs 1,23,456.78 → 123456.78`, parenthesised `(1,200.00) → 1200.00`.
Money is `Decimal` throughout; the fixture stores amounts as **strings** and compares via
`Decimal::from_str`, so no `f64` ever touches a monetary value (FR-007, SC-005).

---

## D6 — Date parsing: port the full format list; `chrono` is locale-independent (VERIFIED)

**Decision**: Port `_DATE_FORMATS` (all 11 non-2-digit-ambiguity entries, in order) and try
each via `chrono::NaiveDate::parse_from_str(token.trim(), fmt)`, returning the first success.
ICICI needs at least `%d/%m/%Y` (rows) and `%b %d, %Y` (the `May 28, 2026` header); porting
the whole list makes `common.rs` reusable by later readers.

**Evidence**: `29/04/2026 → 2026-04-29` (`%d/%m/%Y`), `May 28, 2026 → 2026-05-28`
(`%b %d, %Y`). `chrono`'s `%b`/`%B` use built-in **English** month tables independent of
system locale → deterministic (FR-016). Note `%y` (2-digit year) is unused by ICICI; keep it
in the list but be aware chrono's century pivot differs subtly from Python's — irrelevant here,
flagged for the HDFC/SBI slices.

---

## D7 — `find_last4` without lookaround (VERIFIED)

**Risk**: The strict PAN regex uses lookaround —
`(?<![0-9Xx*])([0-9]{2,6}[Xx*]{2,}[0-9]{4})(?![0-9Xx*])` — which the Rust `regex` crate does
**not** support.

**Decision**: Match the **core** `[0-9]{2,6}[Xx*]{2,}[0-9]{4}` with `find_iter`, then assert
the neighbor chars aren't in `[0-9Xx*]` manually (checking the char before `start` and at
`end`). Return the last 4 chars of the first qualifying match. Port the looser fallback
`(?:[0-9Xx*][ \-]?){12,}[0-9]{4}` (which needs a mask char present) as-is for future readers;
ICICI's PAN is matched by the strict path.

**Evidence**: `4315XXXXXXXX1002 → "1002"`. Anchor-scoping (`find_last4(text, anchor)`) is not
needed for ICICI (whole-text search) but is ported for reuse. See repo memory: *Rust regex has
no lookaround — port with manual neighbor checks*.

---

## D8 — Polarity: `classify(...) -> Direction`, precedence exactly as the web engine

**Decision**: Port `polarity.classify` as
`classify(description: &str, dr_cr_marker: Option<&str>, amount_cell: Option<&str>) -> Direction`
with precedence: (1) explicit marker via `normalise_marker` (strip non `[A-Za-z-]`, uppercase;
`{CR,C,CREDIT,CRDR-CR}`→Credit, `{DR,D,DEBIT,CRDR-DR}`→Debit) → wins; (2) parenthesised amount
(`(..)`) → Credit; (3) any `_CREDIT_KEYWORDS` substring (casefold) → Credit; (4) default Debit.
**The amount's sign/magnitude is never consulted** (FR-008). Map CREDIT→`Direction::Credit`,
DEBIT→`Direction::Debit`.

For ICICI, `direction()` calls `classify(description, caps.name("dir").map(|m| m.as_str()),
None)` — mirroring the web engine's `marker_direction("dir")`, which does **not** pass
`amount_cell` (so ICICI never exercises the parenthesised path; it stays available for reuse).

**Evidence** (from the live reader): row 0 (`CR`) → **Credit**; row 1 (no marker, spend
language) → **Debit**. `_DEBIT_KEYWORDS` is non-functional in Python `classify` (audit/doc
only) — port as a `//` doc comment or omit; it does not affect behavior.

---

## D9 — Privacy-egress gate: dependency guard + determinism (proportionate, per P1 D8)

**Decision** (two-part, both automated, wired into the core gate):

1. **Dependency guard** — `core/scripts/privacy-egress-audit.sh` runs
   `cargo tree -p kaname-core -e normal --prefix none` (the **shipped** graph: default features
   → no `cli`/clap; `-e normal` → excludes dev/build deps, so `serde_json` and `uniffi-bindgen`
   are excluded) and **fails** if any known networking crate appears (denylist: `reqwest`,
   `hyper`, `h2`, `tokio`, `async-std`, `ureq`, `curl`, `isahc`, `surf`, `native-tls`,
   `openssl`, `rustls`, `quinn`, `tonic`, `socket2`, `mio`, `trust-dns`, …). Exposed as
   `make core-privacy-audit`; added to CI's `core` job. Expected: **PASS** on the current tree.
2. **Determinism/purity test** — in `tests/parity.rs`, call `read_icici_statement` twice on the
   same input and assert equal output (proves no clock/locale/network/global-state dependence —
   FR-016/018, SC-007/008).

**Rationale**: Rust can't cheaply assert “no syscalls”; this proves egress-freedom
*structurally* (a networking crate can't even be linked) **and** *behaviorally* (determinism),
which is proportionate for a pure in-memory parser and directly satisfies FR-020.

**`cargo-deny`?** Considered and **deferred**. It could enforce banned crates + license policy
(no GPL/AGPL/LGPL) + advisories in one tool — a strong fit for the constitution — but it adds a
new binary + `deny.toml` for a single-parser slice. Recommend adopting it in a dedicated
supply-chain-gate slice that also wires license/advisory checks. The `cargo tree` script needs
**zero** new tooling now. (App-side: the SwiftUI app adds **no** network entitlement / ATS /
analytics; the parse path is pure Rust — no runtime network monitor is warranted this slice.)

---

## D10 — UniFFI exposure: two records + two exported functions, reuse P1 bridge

**Decision**: `ParsedStatement` and `ParsedTransaction` get `#[derive(uniffi::Record)]`
(alongside `serde` derives for the fixture harness). Reuse the existing `Direction`
(`uniffi::Enum`) and the `Decimal`/`NaiveDate` custom types already declared in `ffi.rs` +
`uniffi.toml`. Export from `ffi.rs`:

```rust
#[uniffi::export] pub fn read_icici_statement(lines: Vec<String>, full_text: String) -> ParsedStatement;
#[uniffi::export] pub fn icici_claims(full_text: String) -> bool;
```

`Option<T>`/`Vec<T>` map to Swift optionals/arrays; `f64` confidence → `Double`. Two functions
(claims + parse) mirror the web engine's recognition/parse separation and make the wrong-issuer
case (US1-S4/FR-002) directly testable over the bridge. The generated Swift is rebuilt by
`make core-xcframework` (before `tuist generate`).

**Rationale**: Purely additive to the P1 surface; no wire-format change; keeps the “boundary in
one file” convention.

---

## D11 — Build/verify ordering & local simulator (reuse P1 gate)

**Decision**: No change to the gate mechanics. `make core-xcframework` **precedes**
`tuist generate` (Makefile `ios-gen: core-xcframework`; CI builds the xcframework first). CI's
iOS job stays on **`macos-15`**; the core job (ubuntu) gains the privacy-audit step. Local
Xcode 26 requires an explicitly-created **“iPhone 16”** simulator for
`make ios-test`/`xcodebuild -destination '...name=iPhone 16...'` (per repo convention).

---

## D12 — Length bounds ported by codepoint (avoid byte-slice panics)

**Decision**: Port the web engine's `[:240]` bounds on `description_raw` and `errored_lines`
using **char-based** truncation (`s.chars().take(240).collect::<String>()`), never `&s[..240]`.
Python slices by codepoint; naive Rust byte-slicing panics on multibyte merchants or short
strings. `truncate_chars(&str, 240)` is a small shared helper in `statement/base.rs`.

---

## D13 — Fixture location & harness path resolution

**Decision**: Golden vectors live at repo-root `fixtures/icici/credit_card/basic.json`
(namespaced dir + a single self-contained JSON: `lines`, `full_text`, `expected`). This refines
the `fixtures/README.md` “input/ + expected/ + word x-positions” proposal for the **line-reader**
case: CC line readers don't need word x-positions (those are for the future bank-ledger reader),
so one bundled JSON is simpler and matches the requester's recommendation. The harness resolves
paths via `env!("CARGO_MANIFEST_DIR")` joined to `../../../fixtures/...`, so it's independent of
the test's working directory and deterministic. ⚠️ Minor sanity-check: this slightly adjusts the
README's proposed layout (documented in `contracts/golden-fixture.md`).

---

## Resolved unknowns summary

| Unknown | Resolution |
|---|---|
| Does Rust regex match Python's captures? | Yes — verified byte-for-byte (D3). |
| Exact `description_raw`? | Includes the serial: `"4262 BBPS Payment received"` (D4, from a live web-engine run). |
| Decimal scale on `10.20`? | Preserved as scale-2; money never float (D5). |
| Lookaround for PAN? | Rewritten with manual neighbor checks (D7). |
| Concrete privacy-egress gate? | `cargo tree` denylist + determinism test; `cargo-deny` deferred (D9). |
| New dependencies? | Only `serde_json` **dev-only**; no new runtime dep (Complexity Tracking). |
