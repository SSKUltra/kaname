# Quickstart — `016-statement-import-vertical`

How to build, verify and reason about this slice. Read
[`research.md`](./research.md) for *why* and [`contracts/`](./contracts/) for *what*.

---

## 0. Shell setup — the one thing that bites everybody

```bash
export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"   # cargo is NOT on the default PATH
```

The Cargo workspace lives under `core/`, so `cargo` needs `cd core` — or just use `make`.

---

## 1. The verification gate (MANDATORY before every PR)

```bash
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # cargo test (unit + parity + store)
make core-privacy-audit # no networking crate, no openssl-sys in the shipped graph
make lint               # swiftlint --strict + swift-format lint + core-lint
make ios-gen            # tuist generate  (depends on core-xcframework)
make ios-test           # simulator build + Swift Testing  (sim named "iPhone 16")
```

### ⚠ Build-order gotcha — this slice changes the FFI surface

`make core-xcframework` regenerates `ios/Generated/` and the xcframework, and
`tuist generate` resolves the xcframework path **at generation time**. So whenever
`Issuer`, `StatementKind`, `LineWords`, `ReaderError`, `detect_issuer`, `read_statement`,
`import_statement` or `NewAccount.last4` change:

```bash
make core-xcframework && make ios-gen     # never a bare `tuist generate`
```

`make ios-gen` already encodes the dependency — always go through it.

### Other traps

- **`rustfmt` reformats your edits.** After a Rust edit, run `make core-fmt` and re-read the
  file before the next edit — your `old_str` may no longer match.
- **`swift-format [Spacing]` rejects trailing inline comments.** Put comments on their own line.
- **Simulator**: create once with `xcrun simctl create "iPhone 16" "iPhone 16"`.

---

## 2. Build order for the work itself (TDD, RED → GREEN)

```text
1  Rust: registry + detect_issuer + read_statement          (RED → GREEN, cargo test)
2  Rust: first_anchor_index helper in ledger_reader.rs      (additive)
3  Rust: schema v6 (accounts.last4) + migration test        (RED → GREEN)
4  Rust: categorize_account_in / find_duplicates_in refactor  ← MUST precede step 5
5  Rust: Store::import_statement (atomic) + atomicity test  (RED → GREEN)
6  make core-fmt && make core-lint && make core-test
7  make core-xcframework                                    ← before any Swift work
8  Swift: StatementTextExtractor + its failure tests
9  Swift: ImportService actor + pipeline tests over the bridge
10 Swift: empty state → progress → summary UI
11 make lint && make ios-test
```

**Step 4 is not optional.** `std::sync::Mutex` is not reentrant: `categorize_account`
(`store.rs:656`) and `find_duplicates` (`store.rs:785`) both call `self.lock()`. Calling either
from inside `import_statement` while the lock is held **deadlocks silently, only on the happy
path with a real import**.

---

## 3. Proving the tie-break is real (do this first — it takes 30 seconds)

Three of the thirteen shipped golden fixtures are claimed by **two** readers today. Replay the
claim predicates to see it for yourself:

```bash
cd /Users/ssk/Projects/kaname && python3 - <<'PY'
import json, glob
card = {"ICICI_CARD":["ICICI Bank"],
        "HDFC_CARD":["HDFC Bank Credit Card","HDFC Bank Credit Cards"],
        "SBI_CARD":["SBI Card","GSTIN of SBI Card"],
        "YES_CARD":["YES BANK"],
        "IOB_CARD":["INDIAN OVERSEAS BANK","iobnet.co.in"],
        "FEDERAL_CARD":["Scapia","Federal Bank"]}
ledger = {"ICICI_BANK":(["Statement of Transactions","ICICI"],["Saving","Current"]),
          "HDFC_BANK":(["HDFC"],["WithdrawalAmt","Savings Account Details","Statementof account"]),
          "FEDERAL_BANK":(["Federal Bank","Statement of Account"],[]),
          "AU_BANK":(["aubank.in"],["Savings Account","Current Account"])}
def claims(t):
    h = t.lower()
    out = [k for k, ms in card.items() if any(m.lower() in h for m in ms)]
    out += [k for k, (a, b) in ledger.items()
            if all(m.lower() in h for m in a) and (not b or any(m.lower() in h for m in b))]
    return out
for f in sorted(glob.glob("fixtures/**/*.json", recursive=True)):
    d = json.load(open(f))
    if not isinstance(d, dict) or "full_text" not in d: continue
    c = claims(d["full_text"])
    if len(c) != 1: print(f"AMBIG {f}: {c}")
PY
```

Expected output:

```text
AMBIG fixtures/federal/bank_account/classic.json : ['FEDERAL_CARD', 'FEDERAL_BANK']
AMBIG fixtures/federal/bank_account/fi.json      : ['FEDERAL_CARD', 'FEDERAL_BANK']
AMBIG fixtures/icici/bank_account/basic.json     : ['ICICI_CARD',   'ICICI_BANK']
```

In all three the **ledger** reader is correct, which is exactly what `(kind_rank, id)` with
`BankAccount = 0` picks. The permanent guard is a Rust test:
`detect_issuer_resolves_every_golden_fixture_to_its_expected_issuer`.

---

## 4. Fixtures — synthetic only, no exceptions

- Statement fixtures live in `fixtures/<bank>/<kind>/*.json` as
  `{ lines, full_text, expected }`. Reuse the thirteen that exist; add
  `first_row_words`/`line_words` where a ledger row-1 bootstrap needs proving.
- New unusable-document fixtures for US3 are **generated at test time** with
  `UIGraphicsPDFRenderer` (text-bearing, image-only, password-protected, truncated bytes, a
  `.pdf`-named text file) — not committed. No binary blobs, and no route by which a real
  statement could enter the repo.
- **No real statements, no real account identifiers, ever** (Constitution V, FR-043, SC-011).
- Ground truth for engine behaviour is captured by **running** the live web engine at
  `/Users/ssk/Projects/finance-tracker-phase/backend` (`.venv/bin/python`) — read-only, never
  with real data.

---

## 5. Manual smoke test (the 4-tap path, SC-001)

1. Fresh install ⇒ empty state explains Kaname, states data stays on device, one **Import** CTA.
2. Tap **Import** ⇒ system document picker.
3. Pick a synthetic supported statement ⇒ progress shows a stage and a working Cancel.
4. Summary shows: issuer display name + last-4, whether the account is new, the period,
   transactions imported, duplicates skipped, categorized/uncategorized, and any warning.
5. Force-quit, relaunch ⇒ the account and its transactions are still there.
6. Import the **same file again** ⇒ no second account, totals unchanged, summary reports
   "N duplicates skipped".

Then the failure matrix — each must produce its own distinct sentence and leave the store
byte-identical: image-only PDF, password-protected PDF (right and wrong password), corrupt
PDF, a `.txt` renamed `.pdf`, a utility bill, cancel mid-parse.

---

## 6. Accessibility gate (release-blocking, Constitution IV)

- Largest accessibility Dynamic Type size — nothing clipped, nothing unreachable.
- Dark Mode.
- **Reduce Transparency** and **Increase Contrast** — contrast holds; no material treatment is
  the only thing carrying meaning.
- VoiceOver — every control, count, amount and warning announced meaningfully; no unlabelled
  elements.

---

## 7. Where things live

```text
core/crates/kaname-core/src/
  statement/registry.rs      NEW — the 10-entry reader registry + tie-break
  statement/ledger_reader.rs +  first_anchor_index (additive)
  ffi.rs                     +  detect_issuer, read_statement (10 legacy exports untouched)
  store.rs                   +  schema v6, import_statement, *_in refactor
  lib.rs                     +  re-exports
  tests/                     +  dispatcher + registry + import-atomicity tests

ios/Sources/Import/          NEW — StatementTextExtractor, ImportService, the views
ios/Sources/RootView.swift   replaced by the real flow
ios/Project.swift            +  .sdk(name: "PDFKit", type: .framework)
ios/Tests/                   +  ImportPipelineTests, StatementTextExtractorTests, a11y/snapshot
```
