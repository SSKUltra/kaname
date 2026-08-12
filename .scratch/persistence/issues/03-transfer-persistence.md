# 03 — Transfer persistence (engine→store wiring)

**What to build:** wire the **already-ported transfer detector** to the encrypted store —
run the **pure** `detect_transfers` over the store's transactions (**cross-account**) and
**tag** each detected self-transfer's two legs. Schema **v3** adds two columns to
`transactions` — `is_transfer` and a shared `transfer_group_id` — and a new
`detect_transfers` orchestrator on `Store` loads every still-unlinked, non-deleted row across
all accounts, runs the pure matcher, and UPDATEs both legs of each pair with a minted
`transfer_group_id` (idempotency guard `WHERE transfer_group_id IS NULL`). The pure engine is
unchanged (already parity-locked against the web engine, `tests/parity.rs`), so this slice is
**fresh SQLite plumbing proven by behavioural tests**, not a new byte-for-byte port. Design of
record: `.scratch/persistence/spec.md`;
`docs/adr/` (transfer detection); Constitution I/II.

**Blocked by:** #01 encrypted-store bootstrap **and** #02 categorization write-back — both
**done** (schema v2: accounts / categories / transactions + categorization facts).

**Status:** resolved (shipped — `57506da`: schema v3 `is_transfer`/`transfer_group_id` +
cross-account `detect_transfers` write-back, `tests/store_transfer.rs`)

## Why this slice

The store persists accounts, categories and transactions, and `categorize_account` closed the
import→categorize→persist loop. The transfer detector, though, is still a pure function over
**passed-in** rows: nothing on-device feeds it the stored transactions or saves which rows
form an internal transfer. This slice closes that loop for **transfer identity** — the store
becomes the source of the rows the matcher compares and the sink for the
`is_transfer` / `transfer_group_id` tags — entirely on-device (Constitution I). It reuses the
proven `detect_transfers` verbatim; **no engine changes.**

This is the first **cross-account** store operation (`categorize_account` was single-account):
a credit-card bill payment pairs a bank Debit with a card Credit on two different accounts, so
the orchestrator reads across the whole database.

## Scope decision — tag-only (category assignment deferred)

The web `transfer_detector` *couples* detection with category assignment (it also sets
`category_id` to **Self Transfer** / **Credit Card Bill Payment**). This slice writes **only**
the transfer identity (`is_transfer` + `transfer_group_id`) and **defers** category assignment
— because `categorize_account` already assigns `CREDIT_CARD_BILL_PAYMENT` via its CC rule and
re-runs over every non-deleted row, so writing a category here would create a
categorize-vs-transfer clobber/precedence problem that deserves its own slice. The
`is_credit_card_payment` split is still surfaced (in the returned summary) so the later slice
can assign categories without re-deriving. `SELF_TRANSFER` and `CREDIT_CARD_BILL_PAYMENT` are
already among the 23 seeded builtins.

## Interface shape (to confirm at implement-time)

Reuse the engine's existing `TransferInput` / `TransferPair` internally; do **not** expose them
on the new method (the orchestrator builds inputs from stored rows itself).

- **Write-back** (the orchestrator):
  - `store.detect_transfers() -> Result<TransferSummary, StoreError>` — loads **every
    non-deleted transaction whose `transfer_group_id IS NULL`, across all accounts**, joined to
    its owning account for `is_credit_card`; builds a `TransferInput` per row
    (`id`, `account_id`, `is_credit_card`, `date`, `amount`, `direction`,
    `description`(=`description_raw`)); runs the pure `detect_transfers`; and for each returned
    pair mints one `transfer_group_id` and UPDATEs **both** legs
    `SET is_transfer = 1, transfer_group_id = ?` guarded by `WHERE id = ? AND
    transfer_group_id IS NULL`. Runs inside a single write transaction.
- **New FFI record:**
  - `TransferSummary { pairs_linked: u32, credit_card_payments: u32 }` — how many pairs were
    linked, and how many of those had a credit-card leg (`TransferPair.is_credit_card_payment`).
    Exported from `lib.rs` alongside `CategorizeSummary`.
- **Readback fields:** `StoredTransaction` gains `is_transfer: bool` and
  `transfer_group_id: Option<String>` (populated by `map_transaction`; `list_transactions`
  SELECT extended). `NewTransaction` is **unchanged** — a freshly-imported row is never a
  transfer until detection runs (columns default to `0` / NULL).

## Schema v3

Forward-only migration, mirroring the v2 `ALTER TABLE … ADD COLUMN` pattern (constant
defaults, so it runs on a populated table):

```sql
ALTER TABLE transactions ADD COLUMN is_transfer INTEGER NOT NULL DEFAULT 0
    CHECK (is_transfer IN (0, 1));
ALTER TABLE transactions ADD COLUMN transfer_group_id TEXT;
```

Both legs of a pair share the minted `transfer_group_id`; a non-transfer row keeps
`is_transfer = 0` and `transfer_group_id = NULL`.

## Acceptance criteria

- [ ] **Schema v3** applied by a forward-only migration and **idempotent**: adds `is_transfer`
  + `transfer_group_id` to `transactions`; re-opening a v3 DB is a no-op (same `user_version`),
  and a **populated v2 DB upgrades to v3 with existing rows intact** (`is_transfer` defaults
  `0`, `transfer_group_id` NULL) — a unit test in `store.rs`, matching the v1→v2 test.
- [ ] `detect_transfers` links a **cross-account credit-card bill payment** (bank Debit +
  card Credit, ±1 day / ±₹1): both legs come back `is_transfer = true` sharing one non-null
  `transfer_group_id`; summary `{ pairs_linked: 1, credit_card_payments: 1 }`.
- [ ] `detect_transfers` links a **bank-to-bank self transfer** (two non-CC accounts):
  `{ pairs_linked: 1, credit_card_payments: 0 }`.
- [ ] **No false positives:** rows that differ in amount beyond ₹1, are same-direction, or sit
  on the **same account** are **not** linked (`is_transfer` stays `false`, group NULL);
  summary zeros. Results **match the pure `detect_transfers`** for the same rows.
- [ ] **Idempotent write-back:** re-running `detect_transfers` links **0** new pairs and leaves
  every `transfer_group_id` unchanged (already-linked rows are excluded from the candidate load
  **and** guarded on UPDATE).
- [ ] **Deleted rows are excluded** from candidates (an `is_deleted = 1` row is never paired).
- [ ] Money / date / direction stay **exact** across the round-trip (`Decimal` / `NaiveDate` /
  `Debit`|`Credit`) — never floats; `is_credit_card` is read from the **owning account**.
- [ ] Every store op returns a typed `StoreError` — **no `unwrap`/`panic` on the FFI path**.
- [ ] **Rust behavioural tests** (temp DB, `tests/store_transfer.rs`): CC bill-payment link;
  bank-to-bank link; no-false-positive (amount / direction / same-account); idempotent re-run;
  deleted-row exclusion; readback of `is_transfer` + `transfer_group_id` via
  `list_transactions`. Plus the v2→v3 upgrade unit test in `store.rs`.
- [ ] **One Swift bridge test** (`ios/Tests/StoreTransferTests.swift`): seed a bank + a card
  account and the two legs, call `detectTransfers()`, and read the persisted `isTransfer` /
  `transferGroupId` back (both legs share the id); assert the summary counts.
- [ ] **Privacy-egress stays green** and the SQLCipher/LibTomCrypt (no-OpenSSL) wiring is
  unchanged.
- [ ] The **Local Verification Gate** passes: `make core-lint && core-test &&
  core-privacy-audit`, then `make lint && ios-gen && ios-test`.

## Explicitly deferred (later slices)

- **Category assignment for transfers** (Self Transfer / Credit Card Bill Payment) and the
  **categorize-vs-transfer precedence** (which engine wins, and not clobbering a transfer tag
  on `categorize_account` re-run). Its own slice — see the scope decision above.
- **Persisting the pair `score`** (a confidence float; identity needs only the group id).
- **Un-linking / manual correction** of a mistaken transfer (turning a user's override into
  state). Arrives with the learning/correction work.
- **Dedup persistence** (supersede state) and **coverage persistence** (needs a new
  `statements` table + transaction provenance) — the sibling engine→store wiring slices.
- **Transfer UI** — reviewing / confirming detected transfers (P3).
