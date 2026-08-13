# Quickstart: Column-Major PDF Extraction Fidelity

**Feature**: `017-column-major-pdf` | **Plan**: [`plan.md`](./plan.md)

Read order for a fresh session: [`spec.md`](./spec.md) → [`plan.md`](./plan.md) →
[`research.md`](./research.md) (R1–R16, the decisions with source evidence) →
[`contracts/`](./contracts/) → `tasks.md` (once `/speckit.tasks` has run) → this file.

---

## The one-sentence problem

The platform's PDF text layer emits a multi-column statement **column-major**, so a printed row
arrives as several unrelated text lines — and the extractor can currently only *split* lines,
never *re-join* them.

## The one-paragraph fix

Discard the text layer's newlines entirely; group words into rows by where they were **printed**
(vertical overlap of glyph ink extents), and emit one line per printed row. That single change both
splits rows the text layer merged and joins columns it split. Ship it **behind** a recognition
change that matches claim markers whitespace-insensitively against the document minus its
transaction rows — because reshaping alone was measured to turn 11 of 13 real statements into
"not recognised".

---

## Build order

Follow the PR split in `plan.md` § *Delivery order*. It is not a preference: **A before C** is the
difference between improving the app and shipping the prototype's regression.

```text
A  Recognition   → core: claim.rs, identity region, whitespace-insensitive matching, G6/G7
B  Registry      → core: ClaimEvidence, 6 renames, sbi BANK_CODE, specificity, G1–G5
C  Extraction    → ios: StatementTextExtractor rewrite, all-page lineWords, per-page fallback
D  Evidence      → fixtures/geometry/*, renderer, GeometryFixtureTests (incl. non-vacuity)
E  Gates         → make reference-check, perf/cancellation, audits, docs
```

Each PR is independently green against the full gate below. No PR leaves `main` in a state where
text is reshaped but markers are still matched literally.

---

## Verification gate (run before every PR — Constitution § iOS Local Verification Gate)

```bash
make core-lint          # cargo fmt --check + clippy -D warnings
make core-test          # unit + parity.rs + dispatcher.rs golden harness
make core-privacy-audit # no networking crate reaches the shipped core
make import-audit       # no networking symbol on the Swift import path
make lint               # swiftlint --strict + swift-format lint --strict
make ios-test           # core-xcframework → tuist generate → simulator build + tests
```

**Non-negotiable outcomes**

| Check | Requirement |
|---|---|
| Every existing golden vector in `fixtures/` passes with **identical** results | FR-029, SC-005 |
| `ExtractionFidelityTests` passes with **unmodified expectations** | FR-028, SC-005 |
| Every geometry fixture passes **and** reads strictly more transactions than the legacy path | FR-037, SC-011 |
| `make core-privacy-audit` and `make import-audit` are green | FR-033, SC-009 |

---

## Smoke test (the shortest path to seeing it work)

1. `make ios-gen && open ios/Kaname.xcworkspace`
2. Run `GeometryFixtureTests` alone. Before PR C it should **fail** on every issuer vector with a
   transaction count of 0 (or far below expected) — that is the bug reproduced under test, and it
   is what FR-037 requires each fixture to demonstrate.
3. Land PR C. The same suite goes green, and the `legacy_max_transactions` assertion keeps proving
   the fixture was never vacuous.
4. Run `ExtractionFidelityTests` — the slice-016 tight-layout merge case must still pass with its
   original expectations. That is the guard against re-opening the opposite bug.

---

## The local, private verification pass (spec Q3 Option A, research R13)

This is a **release gate a person must run**; CI cannot close this slice.

```bash
make reference-check DIR=/path/to/your/own/statements
```

- Runs the real extractor and the real dispatcher over every PDF in `DIR`.
- Prints exactly two facts per file: the issuer display name and the transaction count.
- Writes **nothing** — not to the repository, not to the store, not to a log, not to the network.
- Never prints a line of statement text, a merchant, an amount, a date or an account number.

Record the resulting counts in the PR description (counts only, as slice 016's T123/T129 did).
The target is SC-002: **zero** files importing zero transactions, down from ten.

---

## Adding a geometry fixture (the format is the evidence)

See [`contracts/geometry-fixture.md`](./contracts/geometry-fixture.md) for the schema. The rules
that are easy to get wrong:

1. **Draw column-major.** Every cell of column 1 top-to-bottom, then column 2. Row-major drawing
   produces a fixture that passes before *and* after the fix — worthless.
2. **Header literals come from the reader's own published claim markers**, never from anyone's real
   document.
3. **Everything else is fabricated** — merchants, amounts, dates, account and card numbers.
4. **Declare `legacy_max_transactions`** and make sure it is strictly below the expected count.
5. **One debit and one credit minimum**, so an inverted direction cannot hide (SC-006).

---

## Gotchas discovered during planning

| Gotcha | Where it bites |
|---|---|
| Whitespace-insensitive matching **widens every bare-institution marker at once**. `hdfc_bank::CLAIM_ALL` is literally `["HDFC"]`, and the AU statement contains `HDFC` in a UPI description. | The identity-region projection (contract C2) is what makes the widening safe. Never ship one without the other, and never without gate G7. |
| Two shipped HDFC markers already have their spaces missing (`WithdrawalAmt`, `Statementof account`) — artefacts of a *different* extractor's spacing. | This is why normalization **removes** whitespace rather than collapsing it (research R7). |
| `sbi.rs` sets `BANK_CODE = "SBI_CARD"` while every other reader uses a bare institution. | FR-053. Two fixtures assert it; neither dedup nor transfer detection reads it; no installed base, so no migration. |
| Only `HDFC_SWIGGY_CARD` can prove its product from the document. | ICICI and SBI stay `BankLevel` with the product as a display label (FR-045). FR-051's build gate is what keeps that honest. |
| `lineWords` was page-1-only. | It silently degraded the ledger row-1 bootstrap to `Row1Provisional` whenever the first anchor row was not on page 1. All-page emission fixes it for free (research R11). |
| Words with no usable glyph bounds must **not** be dropped. | FR-007 forbids losing content; they join the band of the nearest preceding word in text order. |

---

## Definition of done

- [x] All ten issuers import 100% of the transactions their geometry fixture prints (SC-001)
- [x] Every geometry fixture fails against the pre-slice extraction path (SC-011)
- [x] Every existing golden vector and the slice-016 parity proof pass unchanged (SC-005)
- [x] Zero issuers regress to "not recognised" (SC-004)
- [x] Zero inverted directions across the fixtures (SC-006)
- [x] Re-import is byte-identical (SC-007)
- [x] 40-page statement stays responsive and cancels within 2 s (SC-008)
- [x] Privacy audits green; zero network requests (SC-009)
- [x] Every added file reviewed: no real merchant, amount, date, account or card number (SC-010)
- [x] **Human-run reference pass recorded**: zero-transaction files down from 10 to 0 (SC-002)
      — run on the holder's own machine with `make reference-check DIR=…`; counts only, below.

### Reference pass — counts only (T116)

13 documents, all on the operator's own machine; nothing written anywhere.

| | Before | After |
|---|---|---|
| Read **zero** transactions | 10 | **0** |
| **Unrecognised** | 2 | **0** |

Two defects were found by this pass and by nothing else:

- **AU Small Finance Bank** was recognised without the header literal R15 was blocked on
  (209 transactions), closing T119 by evidence.
- **Scapia** was recognised but read **0 of its rows**: `federal.rs` allowed exactly one
  character between a row's date and time, and the statement prints `date · time` spaced. Its
  billing-cycle pattern had the same brittleness. Fixed in the reader, pinned by two unit
  tests and by a geometry vector re-modelled on the real layout — which was confirmed red
  against the old reader before it went green against the new one.

The Scapia defect is the argument for this gate: extraction was correct, every geometry
fixture was green, and the card still imported nothing.
