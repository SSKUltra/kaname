# Phase 1 Data Model — Statement Import Vertical (`016-statement-import-vertical`)

**Date**: 2026-08-12 | **Source**: [`spec.md`](./spec.md) Key Entities → [`research.md`](./research.md) decisions

Three layers own state in this slice. Nothing crosses a layer except through the types below.

```text
  Swift (platform)              UniFFI boundary            Rust (kaname-core)
  ────────────────              ───────────────            ──────────────────
  PickedDocument        ──┐
  ExtractedText         ──┼──▶  lines / fullText / LineWords ──▶ Issuer, ParsedStatement
  ImportStage           ──┘                                      ChainResult / ReconcileResult
  ImportSummary         ◀───────  ImportOutcome  ◀────────────── Store (SQLCipher, schema v6)
  ImportFailure         ◀───────  ReaderError / StoreError
```

Money is `rust_decimal::Decimal` ⇄ base-10 `String` ⇄ `Foundation.Decimal` at every hop —
never a float. Dates are `NaiveDate` ⇄ ISO-8601 `String`.

---

## 1. New engine types (Rust, `uniffi`-exported)

### `StatementKind` — `uniffi::Enum`

| Variant | Meaning |
|---|---|
| `CreditCard` | a card statement; reconcile against printed totals; `is_credit_card = true` |
| `BankAccount` | a savings/current ledger; walk the balance chain; `is_credit_card = false` |

**Closed set.** Exhaustive matching is intentional and permitted (research R4); it is not
per-issuer branching.

### `Issuer` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | stable reader identity, e.g. `ICICI_BANK`. **Opaque to the app.** Uniqueness is the tie-break's totality guarantee (FR-015). |
| `display_name` | `String` | user-facing, engine-owned; rendered verbatim (FR-012, FR-033). |
| `bank_code` | `String` | the code already persisted in `accounts.bank_code` / `statements.bank_code`. **Not unique** — 3 codes are shared by a card *and* a ledger reader. |
| `kind` | `StatementKind` | selects the integrity check and the account type (FR-016, FR-023). |

**Validation** — enforced by `cargo test`, not at runtime: `id` unique across the registry;
`display_name` non-empty; `bank_code` equals the backing reader's `BANK_CODE` constant.

**Lifecycle**: minted by `detect_issuer`, handed back unmodified to `read_statement`. The app
never constructs one. An `id` not in the registry ⇒ `ReaderError::UnknownIssuer`.

### `LineWords` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `line_index` | `u32` | index into the `lines` array this geometry describes |
| `words` | `Vec<Word>` | existing `Word { text, x0, x1 }` (`base.rs:38-47`); `x` are layout points, explicitly **not money** |

**Sparse**: an absent `line_index` simply has no geometry. Supplying `[]` is valid and
documented — it degrades row-1 direction to `Row1Provisional` → `NeedsReview`, never to a
confidently wrong direction (research R5).

### `ReaderError` — `uniffi::Error`

| Variant | When |
|---|---|
| `UnknownIssuer { id }` | `read_statement` received an `Issuer` whose `id` is not in the registry |

A programmer error. **Never rendered to a person** (FR-034).

---

## 2. Reused engine types (unchanged)

| Type | Role in this slice | Source |
|---|---|---|
| `ParsedStatement` | the parse result: `lines`, `errored_lines` (FR-018), `period_start`/`period_end`, `card_last4`, printed balances/totals, `confidence` | `statement/base.rs` |
| `ParsedTransaction` | one parsed row: `value_date`, `amount`, `direction`, `currency`, `description_raw`, `bank_code`, `ledger` | `statement/base.rs` |
| `Word` | word text + x-extent for the row-1 bootstrap | `statement/base.rs` |
| `ChainResult` / `ChainStatus` / `Suspect` | bank-ledger integrity verdict (FR-016) | `statement/balance_chain.rs` |
| `ReconcileResult` / `ReconcileStatus` | card integrity verdict, including the neutral `None` (FR-017) | `statement/reconcile.rs` |
| `Direction` | explicit polarity; amounts are always magnitudes (FR-029) | `model.rs` |
| `CategorizeSummary`, `DedupSummary` | the categorized split (FR-030) and duplicates skipped (FR-025) | `store.rs` |

---

## 3. Store types

### 3.1 Schema v6 — one forward-only `ADD COLUMN`

```sql
-- Forward-only schema v6: account identity carries the masked account/card tail, so an
-- import attaches to the right account by (bank_code, is_credit_card, last4) rather than by
-- substring-matching a display name. Constant (NULL) default, so it runs on a populated
-- table exactly as the v2/v3/v4 migrations do.
ALTER TABLE accounts ADD COLUMN last4 TEXT;
```

`SCHEMA_VERSION` 5 → 6; `apply_migration` gains a `6 => …` arm. **No other schema change** —
the v5 `statements` table already satisfies FR-026 field-for-field (research R6).

**Account identity** becomes `(bank_code, is_credit_card, last4)`:

| Case | Resolution | Requirement |
|---|---|---|
| exactly one match | attach | FR-021 |
| no match | create, flag `isNew` in the summary | FR-022, FR-005 |
| `last4` is `NULL` in the parse, exactly one account for `(bank_code, is_credit_card)` | attach to it | FR-024 |
| `last4` is `NULL`, zero or ≥2 candidates | **ask the person** — never guess | FR-024 |

`NewAccount` and `StoredAccount` gain `last4: Option<String>`.

### 3.2 `ImportAccountTarget` — `uniffi::Enum`

| Variant | Fields |
|---|---|
| `Existing` | `id: String` |
| `New` | `name: String`, `bank_code: String`, `is_credit_card: bool`, `last4: Option<String>`, `currency: String` |

The app resolves which (research R7) because FR-024's ambiguous case needs a human.

### 3.3 `ImportRequest` — `uniffi::Record`

| Field | Type | Notes |
|---|---|---|
| `account` | `ImportAccountTarget` | resolve-or-create, inside the transaction |
| `bank_code` | `String` | written to `statements.bank_code` |
| `period_start` | `Option<NaiveDate>` | from the parse; nullable in v5 already |
| `period_end` | `NaiveDate` | from the parse, else max `value_date` (research R6) |
| `needs_review` | `bool` | integrity `NeedsReview` **or** `errored_lines` non-empty (FR-019) |
| `source` | `StatementSource` | always `Statement` in this slice |
| `transactions` | `Vec<NewImportTransaction>` | see below |
| `now` | `String` | ISO-8601, caller-supplied — the core reads no clock (FR-027) |

### 3.4 `NewImportTransaction` — `uniffi::Record`

`date`, `description_raw`, `amount: Decimal`, `direction: Direction`, `currency`,
`source_category: Option<String>`. Deliberately **not** `NewTransaction`: `account_id`,
`statement_id`, `category_id`, `categorised_by` and the timestamps are all filled in by
`import_statement` itself, so a caller cannot construct an inconsistent row.

### 3.5 `ImportOutcome` — `uniffi::Record`

| Field | Type | Feeds |
|---|---|---|
| `account_id` | `String` | the summary's account |
| `account_created` | `bool` | "new account" badge (FR-022, US4 §5) |
| `statement_id` | `Option<String>` | `None` only in the no-period/no-transaction case (research R6) |
| `transactions_inserted` | `u32` | FR-033 |
| `duplicates_linked` | `u32` | "N duplicates skipped" (FR-025) |
| `categorized` / `uncategorized` | `u32` | FR-030 |

---

## 4. Platform (Swift) types

### `PickedDocument`
`url: URL`, transient `password: String?`. Security-scoped access acquired before extraction
and released in a `defer` covering **every** exit path (FR-002). Never copied off-device
(FR-004); the password is never stored (FR-008).

### `ExtractedText`
`lines: [String]`, `fullText: String`, `lineWords: [LineWords]`. The engine's **only** view of
the document (FR-005; Constitution II — the core never opens a PDF).

### `ImportStage` — drives the progress indicator (FR-037)
`reading` → `identifying` → `parsing` → `checking` → `saving` → `categorizing`. Each boundary
is a `Task.checkCancellation()` point (FR-038).

### `ImportSummary` — what the person sees (FR-033)
`issuerDisplayName` (**always shown**, so a tie-break is visible), `last4`, `accountIsNew`,
`period: DateInterval?` (**omitted** when the parse recovered none), `transactionsImported`,
`duplicatesSkipped`, `categorized`, `uncategorized`, `unreadableRows` (= `errored_lines.count`,
FR-018), `integrity: IntegrityOutcome`.

### `IntegrityOutcome` — three states, never two
`.agrees` | `.needsReview` | `.nothingToCheck`. The third must render as **nothing at all** —
never as a pass and never as a fail (FR-017, US5 §3).

### `ImportFailure` — terminal, plain-language, nothing written (FR-031, SC-006)
`.notAPDF`, `.passwordRequired`, `.wrongPassword`, `.noExtractableText`, `.unreadable`,
`.unrecognizedIssuer`, `.cancelled`, `.storageUnavailable`.

**Invariant**: no case carries an engine identifier, an error code, a `bank_code`, a reader
name, or raw `StoreError`/`ReaderError` text (FR-034, SC-007). Each maps to exactly one
hand-written sentence.

---

## 5. State transitions

```text
                    ┌──────────── .cancelled ◀── cancel (any stage before the write)
                    │
Idle ─▶ Picking ─▶ Extracting ─▶ Identifying ─▶ Parsing ─▶ Checking ─▶ Saving ─▶ Summary
          │             │              │                                  │         │
          │             ├─▶ .notAPDF   └─▶ .unrecognizedIssuer            │         └─▶ Idle
          │             ├─▶ .noExtractableText                            │             (dismiss,
          │             ├─▶ .unreadable                                   │              FR-035)
          │             └─▶ .passwordRequired ─▶ prompt ─▶ ┬─▶ Extracting │
          │                                               └─▶ .wrongPassword ─▶ retry / cancel
          └─▶ .unreadable (security-scoped access denied)
                                                                          └─▶ .storageUnavailable
```

**Invariants**

1. Every edge left of `Saving` leaves the store **byte-identical** (SC-006). The only write is
   `import_statement`, and it is one SQLite transaction (FR-031).
2. `Idle → Picking` is guarded by the `ImportService` actor: a second import cannot start while
   one is in flight (FR-032).
3. `Summary` is reachable with `transactionsImported == 0` — a success, not a failure (FR-020).
4. `needs_review` is persisted whenever the integrity check says `NeedsReview` **or**
   `errored_lines` is non-empty; the transactions still import (FR-019).

---

## 6. Requirement → type coverage

| Requirement | Carried by |
|---|---|
| FR-010 / FR-011 | `detect_issuer` → `Issuer`; `read_statement(Issuer, …)` |
| FR-012 / SC-010 | `Issuer` as a record with an opaque `id` + engine-supplied `display_name` |
| FR-014 / FR-015 | registry `(kind_rank, id)` total order (research R3) |
| FR-016 / FR-023 | `StatementKind` |
| FR-018 | `ParsedStatement.errored_lines` → `ImportSummary.unreadableRows` |
| FR-019 | `ImportRequest.needs_review` → `statements.needs_review` |
| FR-021 / FR-022 / FR-024 | `accounts.last4` (**schema v6**) + `ImportAccountTarget` |
| FR-025 | `ImportOutcome.duplicates_linked` (reuses `find_duplicates`) |
| FR-026 | v5 `statements` row + `transactions.statement_id` — **no migration needed** |
| FR-027 | `ImportRequest.now` |
| FR-028 / FR-029 | `Decimal` ⇄ `String` ⇄ `Decimal`; `Direction` |
| FR-030 | `ImportOutcome.categorized` / `uncategorized` |
| FR-031 / FR-038 / SC-006 | `import_statement` = one transaction; all checkpoints precede it |
| FR-032 | `ImportService` actor |
| FR-033 / FR-034 | `ImportSummary`, `ImportFailure` |
| FR-036 / FR-037 | `ImportStage`, actor-isolated pipeline |
