# Quickstart — Indian Overseas Bank (IOB) Credit-Card Reader (build & verify)

**Feature**: `011-iob-cc-reader` | **Date**: 2026-07-17
Walkthrough to build, test, and verify the slice locally, honoring the iOS Local Verification Gate
ordering (xcframework **before** `tuist generate`). Commands run from the repo root unless noted. IOB
**reuses** the ICICI/HDFC/SBI/Yes/Federal gates and adds **no new dependency** and **no new shared
helper** — it is the **sixth and final credit-card reader**, completing the 10-reader set.

---

## Prerequisites
- Toolchain per `rust-toolchain.toml` (stable + iOS targets) and `make bootstrap` (tuist, swiftlint,
  swift-format). iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
- Local Xcode: create an **"iPhone 16"** simulator (the `-destination …,name=iPhone 16,OS=latest`
  used by `make ios-test` must exist).
- `cargo` on PATH (`source "$HOME/.cargo/env"` if needed).

## 0. Ground truth (already captured & verified — no live run needed)
IOB's `expected` is the locked ground truth from the web engine's IOB reader (`iob.py`), and the two
IOB-specific derivations were **re-confirmed by running the real `kaname-core` helpers** (research
D4/D7 + "Verification harness"): the uppercase-month `%d-%b-%Y` parse (`31-MAR-2026 → 2026-03-31`) and
`find_last4(full_text, Some("Credit Card Number")) → "0042"` (no bleed from the adjacent limits
`16000 25091.5`). The exact fixture bytes are in `contracts/golden-fixture.md`. (Optional
re-confirmation from the web repo, `finance-tracker-phase/backend`, with its venv:)
```bash
PYTHONPATH="$PWD" .venv/bin/python - <<'PY'
from app.services.ingestion.statement_readers import iob
lines = ["31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr",
         "04-APR-2026 ExampleStorePurchase 3,500.00 Dr"]
text = ("INDIAN OVERSEAS BANK CREDIT CARD DIVISION\n"
        "Stmt No: 2026CC0000001 Stmt Date: 20-APR-2026 E-Mail: creditcard@iobnet.co.in\n"
        "Credit Card Number Cash Limit (as part of credit limit) Available Credit Limit\n"
        "123456XXXXXX0042 16000 25091.5\n" + "\n".join(lines))
st = iob.reader.read_lines(lines, text)
print(st.period_start, st.period_end, st.card_last4)   # None 2026-04-20 0042
for ln in st.lines: print(ln.value_date, ln.amount, ln.direction, repr(ln.description_raw))
PY
```
Expected: `period_start None`, `period_end 2026-04-20`, `card_last4 0042`; row0 `Credit 1000.00
"ExampleRefundMerchant"`, row1 `Debit 3500.00 "ExampleStorePurchase"`. (The web `st` also carries
`printed_total_*` — **ignore them**; they are out of scope and are not ported, FR-013.)

## 1. Core — format, lint, test (test-first)
```bash
make core-test      # cargo test --all --all-features → unit tests + tests/parity.rs (incl. IOB vector) + determinism
make core-lint      # cargo fmt --check + clippy -D warnings
```
Expected: the parity harness reproduces the web-engine output **exactly** for the IOB vector — rows
`2026-03-31 / 1000.00 / Credit / INR / "ExampleRefundMerchant"` and
`2026-04-04 / 3500.00 / Debit / INR / "ExampleStorePurchase"`
(`period_start` **absent → None**, `period_end 2026-04-20`, `card_last4 "0042"`, `errored_lines []`).
Determinism, wrong-issuer (`iob_claims`), direction-from-marker, and reconciliation-carve-out tests
pass. The uppercase months `MAR`/`APR` parse via the existing case-insensitive `%d-%b-%Y` (no new date
code).

## 2. Privacy-egress gate (inherited — must stay green)
```bash
make core-privacy-audit   # cargo tree denylist over kaname-core's shipped (default, -e normal) deps
```
Expected: `privacy-egress: OK (no networking crate in kaname-core deps)`. IOB adds **no dependency**,
so the shipped graph is byte-identical to before — this gate must remain green with zero changes.

## 3. Build the engine xcframework (MUST precede tuist generate)
```bash
make core-xcframework     # compiles device+sim slices, runs uniffi-bindgen, lipo, create-xcframework
```
Produces `ios/Frameworks/KanameCoreFFI.xcframework` + `ios/Generated/kaname_core.swift` (git-ignored)
— now also exporting `readIobStatement` + `iobClaims` (the records are reused, so no new Swift type).

## 4. iOS — generate, lint, test
```bash
make lint                 # swiftlint --strict + swift-format lint --strict
make ios-test             # ios-gen (depends on core-xcframework) → xcodebuild … -destination 'name=iPhone 16' test
```
Expected: the "core ↔ Swift IOB parse" suite (`ios/Tests/IobParseTests.swift`) passes —
`readIobStatement(...)` returns the two rows with exact `Foundation.Decimal` amounts, correct
directions (`.credit`/`.debit` from the `Cr`/`Dr` markers), `periodStart == nil`, `periodEnd ==
"2026-04-20"`, and **`cardLast4 == "0042"`**; `iobClaims` is `true` for IOB text and `false` for an
ICICI/SBI string.

## 5. Documentation correction (part of this slice — FR-014/015)
IOB was previously mislisted under the **bank-account** readers. Move it to the **credit-card** list in
both docs (doc-only; no build/test needed):
```bash
# docs/HANDOFF.md      — add `iob.py` to the CC list (~:56); remove it from the bank-account list (~:58–59)
# docs/kaname-ios-plan.md — add `iob` to the CC bullet (~:50); remove it from the bank-account bullet (~:51)
git --no-pager diff -- docs/HANDOFF.md docs/kaname-ios-plan.md   # review; leave UNSTAGED (do not commit)
```
Expected after the edit: IOB appears **once**, under credit-card readers, in each file; the CC reader
count reads as six (icici, hdfc, sbi_card, yes_kiwi, federal_scapia, iob).

## 6. Full local gate (what CI runs)
```bash
make core-lint && make core-test && make core-privacy-audit && make lint && make ios-test
```
CI mirrors this unchanged: the **core** job (ubuntu) runs the privacy audit; the **iOS** job stays on
`macos-15` and builds the xcframework before `tuist generate`.

---

## Try the parse (ad-hoc, optional)
The reader is pure — a tiny Rust snippet exercises the single layout without the app:
```rust
let lines = vec![
    "31-MAR-2026 ExampleRefundMerchant 1,000.00 Cr".to_string(),
    "04-APR-2026 ExampleStorePurchase 3,500.00 Dr".to_string(),
];
let full = "INDIAN OVERSEAS BANK CREDIT CARD DIVISION\nStmt Date: 20-APR-2026\nCredit Card Number Cash Limit (as part of credit limit) Available Credit Limit\n123456XXXXXX0042 16000 25091.5".to_string();
let st = kaname_core::read_iob_statement(lines, full);
assert_eq!(st.lines.len(), 2);
assert_eq!(st.lines[0].direction, kaname_core::Direction::Credit); // terminal 'Cr'
assert_eq!(st.lines[1].direction, kaname_core::Direction::Debit);  // terminal 'Dr'
assert_eq!(st.card_last4.as_deref(), Some("0042"));                // masked PAN 123456XXXXXX0042
assert_eq!(st.period_start, None);                                 // IOB prints no range
```

## Add another golden fixture (future readers)
1. Capture ground truth from the web engine (run its reader; never hand-derive `description_raw`).
2. Write `fixtures/<bank>/<kind>/<name>.json` per `contracts/golden-fixture.md` (amounts as
   **strings**; synthetic data only).
3. Add one `Case` row to the harness case table in `tests/parity.rs`. Run `make core-test`.

## Troubleshooting
- **`cargo` not found**: `source "$HOME/.cargo/env"`.
- **`xcodebuild` can't find a destination**: create the "iPhone 16" simulator in Xcode.
- **Swift can't see `readIobStatement`**: rebuild `make core-xcframework` before `tuist generate`
  (generated Swift is an artifact).
- **A date came back in `errored_lines`**: check the month is a real three-letter English abbreviation
  (`MAR`/`APR`/…); the existing `%d-%b-%Y` is case-insensitive so uppercase is fine, but a typo'd month
  won't parse.
- **`card_last4` came back `nil`**: check the mask in `full_text` — `123456XXXXXX0042` exposes four
  trailing digits, so `find_last4` MUST return `"0042"`. A `nil` result means the mask was edited to
  expose fewer than four digits. Conversely, if it returns `6000`/`5091`, the masked-PAN token was
  removed and the matcher fell onto the limit figures — restore `123456XXXXXX0042`.
- **`period_start` came back `Some(...)`**: IOB prints no period range — it MUST stay `None`. Do not
  copy Yes's `Statement Period` scrape into `iob.rs` (FR-010).
- **A `printed_total_*` field is referenced anywhere**: that's the reconciliation carve-out being
  violated — remove it. `statement/iob.rs` must NOT port `_SUMMARY_RE` / the printed-total scrape
  (FR-013), mirroring `yes.rs`.
- **Parity mismatch on `description_raw`**: re-capture from the web reader — never hand-edit the
  expected string; the harness asserts it byte-for-byte (the terminal `Dr`/`Cr` marker and the amount
  are **not** part of the description).
- **Privacy audit false positive**: IOB adds no dep; if a networking crate appears, that's an
  unrelated regression — the gate is working.
