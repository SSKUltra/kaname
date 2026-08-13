# Contract: Document Recognition & the Issuer Registry (engine)

**Feature**: `017-column-major-pdf` | **Owner**: `core/crates/kaname-core/src/statement/`

The FFI surface is **unchanged**: `detect_issuer(full_text) -> Option<Issuer>` and
`read_statement(issuer, lines, full_text, line_words) -> Result<ParsedStatement, ReaderError>`.
What changes is *what text a claim is matched against*, *how it is compared*, and *how competing
claims resolve*. No reader's parsing behaviour changes (FR-043).

---

## C1 — Whitespace-insensitive comparison (FR-012)

```rust
/// Lowercase, then remove every Unicode whitespace character.
fn normalize_for_claim(s: &str) -> String;

/// Claim test used by every reader.
fn claim_contains(haystack_normalized: &str, marker: &str) -> bool {
    haystack_normalized.contains(&normalize_for_claim(marker))
}
```

**Obligations**

- A marker matches regardless of the amount or kind of whitespace between its words, or its
  absence. `"Statement of Transactions"`, `"Statement  of Transactions"` and
  `"StatementofTransactions"` are the same marker.
- Markers are **not** otherwise rewritten: no punctuation stripping, no unicode folding beyond
  ASCII-lowercasing, no stemming. Widening one axis at a time is what keeps FR-014 testable.
- Normalization is applied to haystack and marker by the **same** function, so the relation is
  symmetric and total.
- Pure, deterministic, no allocation per marker beyond the normalized marker string (FR-015).

**Why this is a correctness fix, not a convenience**: `hdfc_bank::CLAIM_ANY` already contains
`"WithdrawalAmt"` and `"Statementof account"` — literals whose spaces were lost by a *different*
extractor. Matching literals against whatever spacing an extractor happens to produce is the wrong
contract.

---

## C2 — The identity region (FR-014, and the evidenced AU/HDFC hazard)

```rust
/// The part of a document that is allowed to identify it.
fn identity_region(full_text: &str) -> String;   // normalized per C1
fn header_region(full_text: &str) -> String;     // first 15 identity lines, normalized
```

**Obligations**

- A line is **row-like** — and therefore excluded from the identity region — iff it contains a
  date in a supported shape (`\d{2}/\d{2}/\d{4}`, `\d{2}/\d{2}/\d{2}`, `\d{2}-[A-Za-z]{3}-\d{4}`)
  **and** an amount (`[\d,]+\.\d{2}`).
- `CLAIM_ALL` / `CLAIM_ANY` / `CLAIM_MARKERS` are matched against `identity_region`, never the raw
  document.
- A `ProductProven` card claim is matched against `header_region` only (FR-044/FR-047).
- Both functions are pure, deterministic and network-free (FR-015).

**Why**: `AU-statment-savings.pdf` contains the literal `HDFC` inside a UPI transaction
description, and `hdfc_bank::CLAIM_ALL` is exactly `["HDFC"]` matched anywhere in the document. It
is held back today only by failing every HDFC `CLAIM_ANY` marker — and C1 widens every such match
at once. Excluding transaction rows removes the whole class. Symmetrically, `HDFC_SWIGGY_CARD` must
claim on its title line (`Swiggy HDFC Bank Credit Card Statement`) and **not** on the ~40
occurrences of `Swiggy` inside its holder's transaction descriptions.

---

## C3 — Claim evidence and specificity resolution (FR-048, FR-050, FR-051)

```rust
pub enum ClaimEvidence { ProductProven, BankLevel }

pub struct ReaderEntry {
    pub id: &'static str,
    pub display_name: &'static str,
    pub bank_code: &'static str,
    pub kind: StatementKind,
    pub evidence: ClaimEvidence,   // NEW
    pub claims: fn(&str) -> bool,  // receives the identity region
    read: fn(&[String], &str, &[LineWords]) -> ParsedStatement,
}

fn evidence_rank(e: ClaimEvidence) -> u8 { match e { ProductProven => 0, BankLevel => 1 } }
```

`detect_issuer` orders candidates by `(kind_rank, evidence_rank, id)` — was `(kind_rank, id)`.

**Obligations**

- A product-level claim always beats a bank-level claim for the same institution and statement
  kind (FR-048).
- Ledger-before-card tie-breaking is **preserved** — three shipped golden fixtures are claimed by
  two readers today and `kind_rank` resolves all three correctly. `evidence_rank` is inserted
  *after* `kind_rank`, so those three outcomes are untouched (FR-013).
- Resolution is total and deterministic; the same text always yields the same issuer (FR-015,
  US2 scenario 4).

**Loud-failure gates (tests, not runtime)**

| Gate | Rule | Requirement |
|---|---|---|
| G1 | For every `bank_code` with ≥ 2 `CreditCard` entries, all must be `ProductProven` | FR-051 |
| G2 | No golden fixture is claimed by two `ProductProven` card entries | FR-048 |
| G3 | Every id matches `^[A-Z0-9]+_BANK$` or `^[A-Z0-9]+_[A-Z0-9]+_CARD$`, prefix == `bank_code` | FR-052 |
| G4 | No `bank_code` contains a product or kind token | FR-046, FR-053 |
| G5 | No `CreditCard` entry claims a bank-account fixture; no `BankAccount` entry claims a card fixture | FR-016 (test-only — research R10) |
| G6 | Every fixture in `fixtures/` resolves to the issuer it resolved to before this slice (modulo the renamed ids) | FR-013, SC-004 |
| G7 | A synthetic statement for issuer X whose descriptions name issuer Y resolves to X | FR-014 |

G5 is deliberately **not** a runtime rule: the spec downgraded FR-016 to unevidenced and warns that
it must never cause a reader to decline a statement of its own kind.

---

## C4 — Registry renames (FR-041 – FR-043, FR-052, FR-053)

| Before | After | `bank_code` before → after | Evidence |
|---|---|---|---|
| `FEDERAL_CARD` "Scapia Credit Card" | `FEDERAL_SCAPIA_CARD` (same display name) | `FEDERAL` → `FEDERAL` | BankLevel |
| `HDFC_CARD` "HDFC Bank Credit Card" | `HDFC_SWIGGY_CARD` "HDFC Swiggy Credit Card" | `HDFC` → `HDFC` | **ProductProven** |
| `ICICI_CARD` "ICICI Bank Credit Card" | `ICICI_AMAZONPAY_CARD` "ICICI Amazon Pay Credit Card" | `ICICI` → `ICICI` | BankLevel |
| `IOB_CARD` "Indian Overseas Bank Credit Card" | `IOB_RUPAY_CARD` "IOB RuPay Credit Card" | `IOB` → `IOB` | BankLevel |
| `SBI_CARD` "SBI Card" | `SBI_CASHBACK_CARD` "SBI Cashback Credit Card" | **`SBI_CARD` → `SBI`** | BankLevel |
| `YES_CARD` "Kiwi (YES Bank) Credit Card" | `YES_KIWI_CARD` (same display name) | `YES` → `YES` | BankLevel |

The four bank-account entries are **untouched** (FR-042). No entry is added or removed.

**Blast radius of `sbi::BANK_CODE`**: two fixtures assert it, and neither the de-duplication nor
the transfer-detection engine reads it. There is no installed base, so no migration is required
(research R9). `scripts/import-path-audit.sh`'s bank-literal check reads its literals out of the
registry and needs no change.

**Only `HDFC_SWIGGY_CARD` is `ProductProven`**, because only the HDFC statement names its product
in the title. `ICICI_AMAZONPAY_CARD` (header reads `CREDIT CARD STATEMENT`) and
`SBI_CASHBACK_CARD` (header names only `SBI Card`, card masked to two digits) carry the product
name as a **display label** over a bank-level claim — FR-045, and the decision recorded in
research R8.

---

## C5 — AU recognition widening (spec Q4, FR-014) — **blocked on an input**

`au_bank::CLAIM_ANY` gains the account-kind literal that `AU-statment-savings.pdf` actually prints
in its header. That literal cannot be read from this repository (the file is private); it is
supplied by the reference-set holder per research R15.

**Obligations when it lands**

- The literal comes from the **header region**, states the account kind or the document title, and
  is never a bare institution name (that is the C2 hazard) nor a token from a transaction row.
- It ships with a synthetic AU geometry fixture carrying that phrase and with the G7 cross-bank
  false-claim cases green.
- If the literal is not available, this change alone is deferred; nothing else in the slice
  depends on it, and the honest outcome for that one file remains "format not recognised yet".

---

## C6 — What does not change

- `read_lines(lines, full_text, first_row_words)` — the reader seam (FR-032).
- `ParsedStatement`, `ParsedTransaction`, `LedgerMetadata`, `DirectionSource`, `Word`,
  `LineWords`, `Issuer`, `StatementKind`, `ReaderError` — every record shape.
- Every reader's row regex, date parsing, direction derivation, period extraction and printed-total
  extraction (FR-043).
- `Decimal` money end to end; explicit `Direction`; no clock, no locale, no network in the core
  (Constitution I & II, FR-021, FR-033).
- The store: **schema v6**, no migration (research R9).
