# 02 — Categorization write-back (engine→store wiring)

**What to build:** wire the **already-ported categorization stack** to the encrypted store —
**persist the facts** it reads (the T2 merchant map, T1 source-category map, T3 rules) and
**save its results** onto transactions (`category_id`, `categorised_by`). Schema **v2** adds
`merchant_map`, `source_category_map`, `rules`, and a `source_category` column on
`transactions`; a new `categorize_account` orchestrator loads the seeded catalog + the stored
facts, runs the **pure** `categorize_batch`, and UPDATEs each row with the winning category +
the stage that fired. The pure engine is unchanged (already byte-parity against the web
engine), so this slice is **fresh SQLite plumbing proven by behavioural tests**, not a new
byte-for-byte port. Design of record: `.scratch/persistence/spec.md`;
`.scratch/categorization/spec.md`; `docs/adr/0005-categorization-deterministic-stack.md`;
Constitution I/II.

**Blocked by:** #01 encrypted-store bootstrap — **done** (schema v1: accounts / categories /
transactions; `Store::open`, migrations, typed `StoreError`).

**Status:** ready-for-agent

## Why this slice

Slice 01 gave us an encrypted store and the 23 seeded categories, but the categorizer is a
pure function over **passed-in** facts and nothing on-device supplies them or saves its
output. This slice closes the **import → categorize → persist** loop entirely on-device: the
store becomes the source of the merchant "memory" (T2), the issuer source-category map (T1)
and the user rules (T3), and the sink for each transaction's `category_id`. Reuses the
proven `categorize_batch` verbatim — no engine changes, no LLM (T4 stays Pro, ADR-0003).

## Interface shape (to confirm at implement-time)

Reuse the engine's existing fact records (`MerchantRule`, `SourceCategoryMapping`, `Rule`,
`Category`, `Decision`, `Stage`, `CategoryRef`) across the FFI — do **not** invent parallel types.

- **Facts in** (populate the tables the engine reads):
  - `store.insert_merchant_rule(rule: MerchantRule) -> Result<i64, StoreError>` (T2)
  - `store.insert_source_category_mapping(m: SourceCategoryMapping) -> Result<i64, StoreError>` (T1)
  - `store.insert_rule(rule: Rule) -> Result<String, StoreError>` (T3; mints/echoes the rule id)
- **Facts out** (for inspection + tests):
  - `store.list_merchant_rules()`, `store.list_source_category_mappings()`, `store.list_rules()`
- **Write-back** (the orchestrator):
  - `store.categorize_account(account_id: String) -> Result<CategorizeSummary, StoreError>`
    — loads the catalog (`list_categories`) + all stored facts, builds a `CategoryTxn` per
    stored transaction (**bank_code + is_credit_card from the owning account**;
    **source_category + description(=description_raw) + amount + direction from the
    transaction**), runs `categorize_batch`, and persists `category_id` +
    `categorised_by` (the `Stage`, e.g. `T2_MERCHANT_MAP`). Returns
    `CategorizeSummary { categorized, uncategorized }`.
- **New transaction field:** `NewTransaction` / `StoredTransaction` gain
  `source_category: Option<String>` (the issuer's own hint that feeds T1). Existing
  `StoreTests.swift` + Rust tests that build a `NewTransaction` are updated for the new field.
- **`category_ref ↔ category_id`:** `CategoryRef::Builtin { code }` ⇒ the seeded code
  (== `categories.id`); `CategoryRef::Custom { id }` ⇒ a user-category id; both FK
  `categories(id)`. On load, the row's `is_builtin` flag reconstructs the `CategoryRef`.

## Acceptance criteria

- [ ] **Schema v2** applied by a forward-only migration and **idempotent**: adds
  `merchant_map`, `source_category_map`, `rules`, and a `source_category` column on
  `transactions`; re-opening a v2 DB is a no-op (same `user_version`), and a v1 DB upgrades
  with existing rows intact.
- [ ] **Facts round-trip** exactly through `MerchantRule` / `SourceCategoryMapping` / `Rule`
  (priority, match types, patterns/values, and the `CategoryRef` preserved). A fact that
  references a non-existent category **fails closed** (FK / typed `StoreError`, no panic).
- [ ] `categorize_account` categorizes the account's **non-deleted** transactions with the
  **existing pure** `categorize_batch` and saves `category_id` + `categorised_by` **matching
  what the pure engine returns** for the same catalog + facts + rows.
- [ ] **First-wins parity through the store**, one assertion per stage: a credit-card
  bill-payment inflow ⇒ `CREDIT_CARD_BILL_PAYMENT` / `CcRule`; a T1 source-category hit; a T2
  merchant hit; a T3 rule hit (lower priority / user-before-system honoured); and a no-match
  row is left **uncategorized** (`category_id` NULL), never guessed.
- [ ] **Idempotent write-back**: re-running `categorize_account` produces identical rows
  (no churn); the returned `CategorizeSummary` counts are stable.
- [ ] **Custom categories** work end-to-end: a user category (a non-builtin `categories`
  row) referenced by a fact and assigned by a decision round-trips as `CategoryRef::Custom`.
- [ ] Money / date / direction stay **exact** across the round-trip (`Decimal` / `NaiveDate` /
  `Debit`|`Credit`) — never floats.
- [ ] Every store op returns a typed `StoreError` — **no `unwrap`/`panic` on the FFI path**.
- [ ] **Rust behavioural tests** (temp DB): v2 migration idempotency + v1→v2 upgrade with data
  intact; fact round-trip + missing-category rejection; `categorize_account` across all four
  stages + the uncategorized fall-through; re-run idempotency; a custom-category case.
- [ ] **One Swift bridge test** (extend `ios/Tests/StoreTests.swift` or a new
  `StoreCategorizationTests.swift`): seed an account + transactions + facts, call
  `categorizeAccount`, and read the persisted `categoryId` / `categorisedBy` back.
- [ ] **Privacy-egress stays green** and the SQLCipher/LibTomCrypt (no-OpenSSL) wiring is
  unchanged.
- [ ] The **Local Verification Gate** passes: `make core-lint && core-test &&
  core-privacy-audit`, then `make lint && ios-gen && ios-test`.

## Explicitly deferred (later slices)

- **Learning / write-back** — turning a user's *manual correction* into a new merchant-map or
  source-category-map row (spec Out-of-Scope; its own slice). `categorize_account` here
  (re)computes every non-deleted row; respecting manual overrides arrives with learning.
- **`matched_rule_id` audit column** on transactions (the `Decision` carries it; persisting it
  is a small later add).
- **Dedup / coverage / transfer persistence** (sibling engine→store wiring slices).
- **Categorization UI** — review / correct / bulk-recategorize (P3).
- **Category CRUD + display metadata** (colour / emoji / localized names) and a category-seed UI.
- **T4 / LLM** categorization — Pro, server-proxied (ADR-0003).
