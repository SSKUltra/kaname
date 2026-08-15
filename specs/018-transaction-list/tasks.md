---
description: "Task list for 018-transaction-list"
---

# Tasks: The Transaction List — See and Scroll What Import Has Been Writing

**Input**: Design documents from `/specs/018-transaction-list/`
**Prerequisites**: `spec.md` (FINAL), `plan.md`, `research.md` (R1–R20), `data-model.md`, `contracts/engine-history.md`, `contracts/platform-seams.md`, `quickstart.md`
**Governing**: `.specify/memory/constitution.md` (wins over everything), `.scratch/HANDOFF.md` §4–§7, `.github/skills/swiftui-liquid-glass/SKILL.md`

**Tests**: **MANDATORY**, not optional. Constitution Principle V and `.scratch/HANDOFF.md` §4 require test-first (RED → GREEN) for every behaviour. Each RED task is sequenced immediately before the implementation task that turns it green, and **every RED task must be observed failing before its GREEN task starts**.

**No test in this slice may be disabled.** Not `@Test(.disabled(…))`, not `#[ignore]`, not commented out. The one test that would historically have been parked — the cross-account dedup determinism proof — is enabled from PR A because PR A fixes the defect behind it (research R17). T156 greps for the escape hatches.

**Organization**: Tasks are grouped by **PR**, and within a PR by **user story**, because the delivery order in `plan.md` § *Delivery order* is mandatory rather than advisory: PR A crosses the FFI and the xcframework path is resolved by Tuist at *generation* time. That reorders the story phases relative to their P-numbers — the mapping is stated in the phase headers and in the *Recommended PR split* table at the end.

| PR | Stories | Why here |
|---|---|---|
| **A — Engine** 🔒 | none (Setup + Foundational) | Crosses the FFI; must merge first |
| **B — The list** 🎯 | US1 (P1), US2 (P2), US4 (P4) | First demoable slice |
| **C — Filter and honesty** | US3 (P3), US7 (P7) | Needs B's list to exist |
| **D — What the engine already knows** | US5 (P5), US6 (P6) | Per-row detail + the a11y suite |
| **E — Live and fast** | US8 (P8) + Polish | Anchor logic needs B's paging and C's filter |

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared state, no dependency on an incomplete task)
- **[Story]**: `[US1]`…`[US8]`. Setup, Foundational, Design and Polish tasks carry **no** story label.
- Every task names an exact file path.

## Path Conventions

Two-layer repo (`plan.md` → Project Structure):

- **Engine**: `core/crates/kaname-core/src/`, `core/crates/kaname-core/tests/`
- **App**: `ios/Sources/`, `ios/Tests/`, `ios/UITests/`
- **Gates**: repo-root `Makefile`, `scripts/import-path-audit.sh`
- `ios/Project.swift` uses `sources: ["Sources/**"]` / `["Tests/**"]` globs, so **no project-file edit is needed** for the new `ios/Sources/Transactions/` directory or the new test files.

## Non-negotiables encoded in this list

1. **⚠️ FFI build ordering.** After any change to `core/src/ffi.rs` or any `#[uniffi::export]`: `make core-xcframework` **then** `make ios-gen`. Never a bare `tuist generate` — it resolves the xcframework path at generation time and yields a "cannot find `HistoryPage` in scope" error that looks like a Swift problem and is not (T041, T043).
2. **⚠️ `ios/Sources/Import/ImportService.swift` is at exactly 400 lines** — SwiftLint's default `file_length` warning threshold, which `make lint`'s `--strict` turns into a build failure (`ios/.swiftlint.yml` sets `line_length` to 120 and leaves `file_length` at its default). **No task may add a net line to it without removing one first.** T067 removes the N+1 count block; T137 spends the headroom that creates and re-checks `wc -l` (≤ 400).
3. **⚠️ R17 is fixed here, in PR A** (Phase 2A). Order dedup's account groups by `accounts.rowid`, proven deterministic **across processes**. It is a **tie-break change only**: `dedup.rs`'s layers are untouched, no same-institution guard is added, and which pairs match does not change.
4. **⚠️ Transfer detection stays unwired** (research R18, FR-018). No task calls `detectTransfers()` from `ios/Sources/`. The marking is built and tested against a store where the flag is set **by the test**. **No task name, test name, string or release note may imply the app detects transfers** — T130 audits this mechanically.
5. **The live-row rule is one definition.** `LIVE` in Rust is byte-identical to `idx_txn_live_account_date`'s `WHERE` clause (L6), and every count this slice introduces comes from `account_summaries()` (FR-008). A read that forgets the rule loses its index and the plan-shape gate goes red.
6. **Money is `Decimal` / `rust_decimal` at every hop, including through formatting.** No `Double`, no `String(format:)`, no `minimumScaleFactor` on an amount.
7. **iOS 26 / Liquid Glass, unconditional.** Never `#available(iOS 26`, never `*Material`, `UIVisualEffectView` or `UIBlurEffect` under `ios/Sources/`; `make import-audit` fails the build on all of them. Glass appears on exactly one element of this screen — the filter chrome — on an opaque bar. Never under rows of numbers.
8. **Zero network I/O.** The audit's networking scan is widened from `ios/Sources/Import` to `ios/Sources` **in the same PR that creates `ios/Sources/Transactions/`** (T052, research R19). A gate that lands later is a gate that was absent when it mattered.
9. **No real statement, merchant or account identifier** in any fixture, at any point (FR-064, SC-017).
10. **Verification gate before every PR**: `make core-lint && make core-test && make lint && make ios-test`, plus `make import-audit` (and `make core-privacy-audit` for PR A).

---

# PR A — Engine 🔒

*Schema v7, the `LIVE` constant, `history_page`, `account_summaries`, the six records, `ffi.rs` exports, the O/L/P/F/S suites, the migration test, and the R17 tie-break fix. Merges first.*

## Phase 1: Setup

**Purpose**: A green baseline and a synthetic corpus that measures what it claims to measure — before a line of engine code changes.

- [x] T001 Establish the green pre-change baseline: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` then run `make core-lint && make core-test && make core-privacy-audit && make import-audit` from the repo-root `Makefile`; record the passing test count in the PR description so any later regression is attributable.
- [x] T002 [P] Create `core/crates/kaname-core/tests/common/mod.rs` — the synthetic corpus builders every engine suite shares, per `data-model.md` §7 and research R20. `correctness_corpus(store)` writes through the **real** `Store::import_statement` and must satisfy the fixture contract: ≥ 3 accounts; ≥ 2 currencies including one `en_IN` does not localise; a **globally unique amount and a globally unique description per row**; ≥ 1 date carrying rows from more than one account **with different amounts**; ≥ 1 account whose statement parsed zero rows; ≥ 1 account whose every row is superseded; ≥ 1 deleted row; ≥ 1 date group larger than one page; ≥ 1 empty description, ≥ 1 very long description, ≥ 1 amount with 7+ integer digits. `perf_corpus(conn, accounts, rows)` writes by **direct SQL** (151 ms versus 11.8 s through the import path) and builds both the 10,000-row/8-account corpus and its 200-row/2-account twin. Synthetic throughout — no real merchant, no real account identifier.
- [x] T003 [P] Prove the corpus does not de-duplicate itself before anything measures it: add `the_correctness_corpus_supersedes_exactly_the_rows_it_means_to` to `core/crates/kaname-core/tests/common/mod.rs`'s own test module, asserting `SELECT count(*) FROM transactions WHERE superseded_by IS NOT NULL` equals the number the fixture deliberately supersedes. R20's first attempt silently collapsed 8,750 of 10,000 rows; a perf gate over an eighth of its claimed corpus is worse than no gate.
- [x] T004 [P] Establish the R17 change list before touching it: `grep -rn "created_at" core/crates/kaname-core/src/store.rs core/crates/kaname-core/tests` and confirm that `load_dedup_candidates_groups_by_account_oldest_first_and_excludes_linked` (`core/crates/kaname-core/src/store.rs:2168`) is the **only** shipped test pinning the `a.created_at, a.id` tie-break. Record the finding in the PR description; T009 depends on the list being complete.

**Checkpoint**: Baseline green, corpus builders exist and are proven honest, the R17 blast radius is known.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The whole engine surface of this slice. **No platform work may begin until Phase 2 is complete and the xcframework is regenerated.**

### Phase 2A — ⚠️ R17: the cross-account dedup tie-break (fix, not a deferral)

> Two accounts each carrying an identical row supersede one another, and **which one loses is decided by 128 random bits** — `a.id` is `lower(hex(randomblob(16)))` (`store.rs:1257`) and two accounts created in the same second share `a.created_at`. Running the same import twice on two fresh databases produced opposite losers (research R17, measured). Fixed here, in PR A, by the repo owner's decision.
>
> **Scope discipline**: this is a **tie-break** change. Do not touch `core/crates/kaname-core/src/dedup.rs`. Do not add a same-institution guard. Do not change which pairs are considered duplicates. Whether identical rows in two accounts should collapse *at all* remains a recorded finding for a slice that owns dedup.

- [x] T005 Create `core/crates/kaname-core/tests/store_dedup_determinism.rs` with the shared probe `fn supersession_winner(db_path: &Path) -> (String, String)`: on a fresh temp database, import through the **real** `Store::import_statement` two accounts that each carry the identical row `2025-03-04 / COFFEE SHOP / 250.00 / Debit` plus one row unique to that account, then return `(surviving_account_name, superseded_account_name)` read back from `superseded_by`. Synthetic names only. This is fixture code — it has no RED step of its own.
- [x] T006 RED: add `the_same_import_supersedes_the_same_row_on_every_fresh_database` to `core/crates/kaname-core/tests/store_dedup_determinism.rs` — run T005's probe over **10** fresh temp databases in one process and assert the superseded account is identical every time. **Observe it fail against unmodified code** and record which accounts lost across the 10 runs; a run where it accidentally passes proves nothing and must be re-run.
- [x] T007 RED: add the cross-process proof `the_supersession_winner_is_the_same_in_a_re_executed_process` to `core/crates/kaname-core/tests/store_dedup_determinism.rs`. Re-exec `std::env::current_exe()` with `--exact dedup_probe_child` and `KANAME_DEDUP_PROBE=1` set; `dedup_probe_child` is a `#[test]` that returns immediately unless that variable is present, and otherwise prints T005's superseded account name to stdout. The parent runs the probe itself and asserts the child's answer matches. **A single-run, single-process assertion would have passed against the shipped defect** (R17) — this is the assertion that actually holds the guarantee. The child must use its own temp directory and clean it up; no sleeps, no retries.
- [x] T008 GREEN ⚠️ Fix 1 of 2 — the tie-break: in `load_dedup_candidates` (`core/crates/kaname-core/src/store.rs:1388–1394`) replace `ORDER BY a.created_at, a.id, t.rowid` with `ORDER BY a.rowid, t.rowid`, and rewrite the doc comment above it (`store.rs:1385–1387`) so it names **`accounts.rowid`** — the same single account ordering `Store::list_accounts()` uses and the one the person sees (research R3, FR-030) — as what decides which side of a duplicate survives. Nothing in `dedup.rs` changes.
- [x] T008a RED: add `two_credit_cards_each_keep_their_own_identical_row` to `core/crates/kaname-core/tests/store_dedup_determinism.rs` — two **credit-card** accounts, each carrying `2025-03-04 / COFFEE SHOP / 250.00 / Debit`; assert **both rows survive** with `superseded_by == None`. Two cards printing the same coffee on the same day are two real purchases. **Observe it fail**: today one is superseded. This is US1 AS-6 as the spec actually words it — "neither is mistaken for, merged with, or hidden by the other".
- [x] T008b RED: add `a_bank_ledger_and_a_card_still_collapse_the_same_purchase` to the same file — one **bank** account and one **credit-card** account carrying that identical row; assert one **is** superseded. This is 013's whole purpose (`specs/013-cross-source-dedup/spec.md:15`, "the same purchase appears in two different statements … a bank-account ledger and a credit-card statement") and T008c must not break it. Expected to pass before and after; it is the regression fence around the narrowing.
- [x] T008c GREEN ⚠️ Fix 2 of 2 — the source guard: cross-account de-duplication MUST only compare accounts of **different kinds** (one bank ledger, one credit card). Carry `accounts.is_credit_card` out of `load_dedup_candidates` (add it to the `SELECT` and group as `(is_credit_card, rows)`), and in `find_duplicates_in` (`store.rs:1147`) build each incoming group's `existing` list from **only** the pooled rows of the opposite kind, mapping `existing_index` back through that filtered index list. Same-kind pairs are never offered to the matcher. `dedup.rs` — its layers, its thresholds, what it considers a match — is **untouched**; this narrows *which pairs are asked about*, nothing else.
- [x] T009 GREEN: rewrite the shipped unit test `load_dedup_candidates_groups_by_account_oldest_first_and_excludes_linked` (`core/crates/kaname-core/src/store.rs:2168`) — rename it to `load_dedup_candidates_groups_by_account_rowid_and_excludes_linked`, replace the comment that currently reads "ordering must follow `created_at`, not insertion order" with the `accounts.rowid` rationale, flip the expectation to `vec![vec!["n1"], vec!["o1"]]` (the `newer` account is inserted first, so it now comes first), and extend it for the `is_credit_card` the group now carries. Per T004, this is the only shipped test that pins the old tie-break; any other hit found there is handled here too.
- [x] T010 GREEN: T006, T007, T008a and T008b all pass. Run `cargo test --test store_dedup_determinism` twice in a row from a clean state and confirm the same winner both times — the point of the fix is that a second run cannot disagree with the first.
- [x] T011 [P] Add `the_surviving_row_is_on_the_account_list_accounts_returns_first` to `core/crates/kaname-core/tests/store_dedup_determinism.rs`: the account whose row survives is the one `Store::list_accounts()` yields first, pinning the store's dedup tie-break to the *same* account ordering the front door and `history_page` use. One account ordering in the app, asserted rather than assumed.
- [x] T012 **GATE** `make core-fmt && make core-test` — T006, T007 and T011 green, and `core/crates/kaname-core/tests/store_dedup.rs`, `store_import.rs` and `store_categorization.rs` are **unchanged and still green**, proving the tie-break change altered no matching behaviour.

### Phase 2B — Schema v7 and the `LIVE` constant

- [x] T013 RED: add `migrating_v6_to_v7_preserves_existing_rows` to the `#[cfg(test)] mod tests` block in `core/crates/kaname-core/src/store.rs`, mirroring `migrating_v5_to_v6_preserves_existing_rows`: build a **populated** v6 database (accounts + transactions + statements), open it, assert `PRAGMA user_version == 7`, every pre-existing row is byte-identical, and `idx_txn_live_account_date` exists in `sqlite_master` carrying its partial `WHERE` clause (M1, M2).
- [x] T014 RED: add `reopening_a_v7_store_is_a_no_op` to `core/crates/kaname-core/tests/store.rs` beside `migration_is_idempotent_across_reopens` — a re-open must not re-run the migration, re-create the index, or alter a row (M3).
- [x] T015 GREEN: add `const SCHEMA_V7: &str` to `core/crates/kaname-core/src/store.rs` (after `SCHEMA_V6` at `store.rs:172`) exactly as `data-model.md` §1 states — `CREATE INDEX idx_txn_live_account_date ON transactions(account_id, date DESC) WHERE is_deleted = 0 AND superseded_by IS NULL;` — and bump `const SCHEMA_VERSION: i64` from `6` to `7` at `store.rs:41`. `DESC` and `partial` are both load-bearing and measured (research R4): an ASC index costs `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`.
- [x] T016 GREEN: add the `7 => { tx.execute_batch(SCHEMA_V7).map_err(StoreError::migration) }` arm to `apply_migration` in `core/crates/kaname-core/src/store.rs:1201`, following the shipped v2–v6 pattern exactly. Forward-only; no table rebuild, no foreign-key disable, no row read or written.
- [x] T017 RED: add the L6 structural assertion `the_live_constant_is_byte_identical_to_the_v7_index_predicate` to the `#[cfg(test)] mod tests` block in `core/crates/kaname-core/src/store.rs` (it lives here, not in an integration test, because `LIVE` is private): read `sql` for `idx_txn_live_account_date` out of `sqlite_master`, extract the text after `WHERE`, and compare it to `LIVE` **byte for byte**. If someone paraphrases either one, this goes red before anyone sees wrong rows.
- [x] T018 GREEN: add `const LIVE: &str = "is_deleted = 0 AND superseded_by IS NULL";` to `core/crates/kaname-core/src/store.rs` with the doc comment from `contracts/engine-history.md` §5, and build `SCHEMA_V7`'s `WHERE` clause from `LIVE` (`format!`/`const_format`-free concatenation is fine) so the two cannot drift.
- [x] T019 **GATE** `make core-fmt && make core-test` — T013, T014 and T017 green; every shipped store test unchanged.

### Phase 2C — `history_page` and `account_summaries`

> One prepared statement per account, k already-sorted streams merged in Rust, `self.lock()` taken **exactly once** per call with `*_in(&conn, …)` helpers thereafter. `std::sync::Mutex` is not reentrant — 016 learned this the hard way and it is why the lazy-handle design was rejected outright (research R1).

- [x] T020 [P] RED: create `core/crates/kaname-core/tests/history_order.rs` with O1–O7 over T002's correctness corpus — O1 rows non-increasing by date; O2 same-date rows of **different** accounts in `list_accounts()` order; O3 same-date rows of the **same** account in insertion (printed) order; O4 the concatenation of every page equals a brute-force sort of every live row by `(date DESC, account_position ASC, rowid ASC)`; O5 ten consecutive full reads return byte-identical sequences; O6 importing a further account leaves the relative order of every pre-existing row unchanged; O7 `history_page`'s account sequence equals `list_accounts()`'s id sequence.
- [x] T021 [P] RED: create `core/crates/kaname-core/tests/history_live.rs` with L1–L5 — L1 a deleted row never appears in any page, filtered or not; L2 a superseded row never appears, filtered or not; L3 importing the same statement twice leaves the full page sequence identical in contents, count **and** order; L4 `sum(account_summaries().live_transaction_count)` equals the row count of a full unfiltered read; L5 per account, `live_transaction_count` equals the row count of a read filtered to it.
- [x] T022 [P] RED: create `core/crates/kaname-core/tests/history_paging.rs` with P1–P5 — P1 pages of 1, 7, 30 and 200 concatenate to the same sequence; P2 no row appears twice and none is skipped; P3 `rows.len() < limit` ⇒ `cursor == None`; P4 an import **between** two page reads neither duplicates nor skips a row already returned (keyset, not offset); P5 an `account_id` naming no account yields an empty page with `cursor == None`, not an error.
- [x] T023 RED: append F1–F3 to `core/crates/kaname-core/tests/history_paging.rs` — F1 a filtered read returns exactly that account's live rows; F2 a filtered read's order is the unfiltered order with the other accounts removed; F3 the filtered and unfiltered reads execute the **same SQL text** (assert against the exported `PAGE_SQL` constant — structural proof that a filter is not a second code path).
- [x] T024 [P] RED: create `core/crates/kaname-core/tests/history_perf.rs` with the plan-shape gates S1–S2 over **both** corpora from T002 — S1 `EXPLAIN QUERY PLAN` of the page query contains no `SCAN` and no `USE TEMP B-TREE`; S2 the plan names `idx_txn_live_account_date`. These are the assertions that make the live rule structural rather than remembered.
- [x] T025 RED: append the wall-clock gates S3–S6 to `core/crates/kaname-core/tests/history_perf.rs` — S3 first page < 25 ms on 10,000/8; S4 max page over a full walk < 25 ms; S5 per-account first-page cost varies ≤ 20% between the 200/2 and 10,000/8 corpora (SC-008b; measured at 13%); S6 a filtered (`k = 1`) page < 25 ms on 10,000/8. The 25 ms bound is ~100× the measured 254.75 µs deliberately: it catches a lost index or an N+1, not a loaded CI machine.
- [x] T026 GREEN: add `HistoryCursor`, `AccountMark` and `HistoryQuery` as `uniffi::Record`s to `core/crates/kaname-core/src/store.rs`, exactly per `contracts/engine-history.md` §1. `HistoryCursor.marks` holds one resume point per account **still producing rows** — an exhausted account is absent, so the cursor shrinks as the person scrolls.
- [x] T027 GREEN: add `HistoryRow`, `HistoryPage` and `AccountSummary` as `uniffi::Record`s to `core/crates/kaname-core/src/store.rs`. `HistoryRow` carries **no** `superseded_by`, `dedup_layer`, `statement_id`, `categorised_by`, `transfer_group_id`, `is_deleted`, `rowid`, `created_at` or `updated_at` — they are absent so they cannot leak into a view (FR-019, SC-016). `AccountSummary.has_only_excluded_rows` is a **bool, not a count**, deliberately: a count that does not use the live rule would violate FR-008 the moment someone rendered it.
- [x] T028 GREEN: implement the ordering comparator as a private pure function over `(date, account_position, rowid)` in `core/crates/kaname-core/src/store.rs`, and unit-test it directly in the file's `#[cfg(test)] mod tests` — totality, antisymmetry and the three tie-break levels. This is the **only** place the order is expressed outside SQL, and `data-model.md` §2 is the other; a test pins them to each other (O4).
- [x] T029 GREEN: add `const PAGE_SQL: &str` to `core/crates/kaname-core/src/store.rs` — the per-account keyset statement from `contracts/engine-history.md` §5 verbatim, with its `WHERE` built from `LIVE` — and prepare it once per call. A first page binds `?2 = '9999-12-31'`, `?3 = 0`: the identity cursor, so there is no separate first-page code path.
- [x] T030 GREEN: resolve `account_name`, `account_last4` and `category_name` in Rust from two maps read once per call via `*_in(&conn, …)` helpers in `core/crates/kaname-core/src/store.rs`. **No JOIN** — a join changes the plan and defeats S1/S2.
- [x] T031 GREEN: implement `Store::history_page(&self, query: HistoryQuery) -> Result<HistoryPage, StoreError>` in `core/crates/kaname-core/src/store.rs`: take `self.lock()` **once**, run `PAGE_SQL` once per account in scope, merge the k already-sorted buffers with T028's comparator, emit `limit` rows, and build the resume cursor from the last row emitted per account. Clamp `limit` to `1..=200` — clamped, never an error: a page of 0 is an infinite scroll loop in the caller.
- [x] T032 GREEN: implement the filter as `k = 1` over the same `PAGE_SQL` in `core/crates/kaname-core/src/store.rs` — an `account_id` naming no account yields an empty page and `cursor == None`. There is no second query, no second ordering and no second population (F1–F3, FR-042).
- [x] T033 GREEN: implement `Store::account_summaries(&self) -> Result<Vec<AccountSummary>, StoreError>` in `core/crates/kaname-core/src/store.rs`: `list_accounts()` order, one grouped count under the `LIVE` predicate and the v7 index, `has_only_excluded_rows` true iff the account has ≥ 1 row in `transactions` and `live_transaction_count == 0`. Same single `self.lock()` discipline.
- [x] T034 GREEN: map every failure to `StoreError::Sql` in `core/crates/kaname-core/src/store.rs` — a corrupt amount, date or direction surfaces as an error and never panics, exactly as `map_transaction` already does. Add the Z2 assertion `no_history_error_carries_a_description_amount_date_or_account_id` to `core/crates/kaname-core/tests/history_live.rs`, forcing each failure and asserting the rendered error string contains none of the corpus's descriptions, amounts, dates or account ids (FR-063).
- [x] T035 GREEN: re-export `HistoryQuery`, `HistoryCursor`, `AccountMark`, `HistoryRow`, `HistoryPage` and `AccountSummary` from `core/crates/kaname-core/src/lib.rs`.
- [x] T036 GREEN: export both reads across the FFI from `core/crates/kaname-core/src/ffi.rs` — `#[uniffi::export] impl Store { history_page, account_summaries }`. `Decimal` and `NaiveDate` use the custom types already registered at `ffi.rs:60` and `ffi.rs:67` (base-10 `String` → `Foundation.Decimal`, ISO-8601 `String`); money never becomes a float.
- [x] T037 **GATE** `make core-fmt && make core-test` — the O, L, P, F and S suites all green, `Store::list_transactions` still returning its raw view with `ORDER BY rowid` and its existing tests untouched (`contracts/engine-history.md` §3).

### Phase 2D — Engine verification gate and FFI regeneration

- [x] T038 **GATE** `make core-lint` — `cargo fmt --check` + `clippy -D warnings` (repo-root `Makefile`).
- [x] T039 **GATE** `make core-test` — the whole engine suite: the new O/L/P/F/S files, the v6→v7 migration test, the R17 determinism suite, and every shipped test unchanged.
- [x] T040 **GATE** `make core-privacy-audit` (Z1) — zero new crates and zero new dependencies were added, so this must stay green **unchanged**. If it moved, something was added that should not have been.
- [x] T041 ⚠️ **FFI ordering** `make core-xcframework` — regenerates `ios/Generated/` and `KanameCoreFFI.xcframework` for the six new records and two new methods. This **must** run before any `tuist generate`.
- [x] T042 Confirm no shipped Swift call site broke: the engine change is purely additive (no existing signature changed), so `ios/Tests/StoreTests.swift`, `ios/Tests/StoreTransferTests.swift` and `ios/Sources/Import/ImportService.swift` must compile untouched. If any of them needs an edit, stop — something non-additive was changed.
- [x] T043 **GATE** `make ios-gen && make ios-test` — never a bare `tuist generate`. Every shipped Swift suite must be green against the regenerated bindings **before** a line of new Swift is written.
- [x] T044 **GATE** `make import-audit` — unchanged in this PR; the networking-scan widening lands in PR B with the directory it guards (T052, research R19).

**Checkpoint**: 🔒 The engine is complete, gated and regenerated. The order is total, the live rule is structural, the dedup tie-break is deterministic across processes, and no test is disabled. Platform work may begin.

---

# PR B — The list 🎯

*`ios/Sources/Transactions/` (six files), `StoreProvider`, the row with its accessibility layout from the start, incremental date grouping, the `NavigationStack` destination, front-door rows become links, the front-door count switches to `account_summaries()`, and the widened networking audit. The first demoable PR. **US1, US2, US4.***

## Phase 2.5: Design contract (before any UI)

**Purpose**: Fix the visual and copy contract before building. Kaname has no Figma tooling; the visual contract of record is `contracts/platform-seams.md` §3–§4 plus research R12/R13 and `.github/skills/swiftui-liquid-glass/SKILL.md`.

- [x] T045 [Design] Walk the glass application points for this screen against `.github/skills/swiftui-liquid-glass/SKILL.md`: glass on **exactly one** element — the filter chrome, in a `GlassEffectContainer`, on an **opaque** bar via `.safeAreaBar(edge: .bottom)`; **never** under rows or numbers ("the transaction list, statement rows, and any table of numbers stay on opaque backgrounds" is the skill's own words); the app's accent (`ios/Sources/Theme.swift`), never the system default. Record any deviation as a note in this file **before** building — do not edit the FINAL design artifacts.
- [x] T046 [Design] Write the copy deck: the exact user-facing sentence for each of the **six** empty states (`data-model.md` §6), the direction words ("debit" / "credit"), the uncategorized label, the transfer marking, the filter chrome's wording and the row accessibility sentence's shape. Every sentence is hand-written. The only engine-supplied strings permitted on screen are the account name, the description as printed, and the category name. **No sentence may imply transfers are detected** (FR-018).
- [x] T047 [Design] Trace the state machine in `data-model.md` §5 and the empty-state table in §6 against the six rows: confirm every branch has a destination, that rows 4–6 are distinguishable from row 1 with only `[AccountSummary]` and the filter in hand, and that nothing needs a field `AccountSummary` does not carry. If a branch cannot be decided from those two inputs, stop and raise it rather than adding a count that breaks FR-008.

### Design contract — RECORDED (T045–T047)

*Written before any UI, per T045's instruction. The FINAL artifacts (`spec.md`, `plan.md`,
`data-model.md`, `contracts/`) are **not** edited; everything this walk found is recorded here.
T056, T060, T061, T088, T096, T098 and their RED suites build from this section.*

---

#### T045 — The glass walk

**Application points, element by element.** Glass appears on exactly one *region* of this
screen, and never on anything a figure is read against.

| Element | Glass? | Why |
|---|---|---|
| Transaction rows, amounts, dates, account names | **No** — opaque `List` rows | FR-068, W1; the skill's own words: "the transaction list, statement rows, and any table of numbers stay on opaque backgrounds" |
| Date group headers (`Section` headers) | **No** — system `List` chrome, unmodified | skill: don't re-skin system chrome |
| Navigation bar + back affordance | **System** — gets Liquid Glass for free | skill: let the system own its chrome |
| The filter bar's **background** | **No** — opaque `.background(.background)`, pinned by `.safeAreaBar(edge: .bottom)` | FR-069, W3 |
| The scope button + the clear button **inside** that bar | **Yes** — `.buttonStyle(.glass)`, both in one `GlassEffectContainer(spacing: 12)` | the screen's only glass |
| The transfer marker, the uncategorized label, the direction sign | **No** | they live inside rows; a static badge never gets glass (skill: `.interactive()` only where there is interaction) |
| An empty state's action button | **Glass, non-prominent** — except the one state where it is the only glass on screen (see D2) | at most one prominent element per screen |

**Rules this screen commits to:**

- **`.buttonStyle(.glass)`, never a hand-glassed `Text` with a tap gesture**, and never an
  additional `.glassEffect(.regular.interactive())` on top of a `Button` — the built-in style
  already carries interactivity.
- **One container, one shape.** Both bar buttons are `.capsule` (the default). Mixed radii inside
  one container is the single most common way a glass screen reads wrong.
- **Morphing, not cross-fading.** The clear button appears and disappears with the filter, so it
  and the scope button carry `@Namespace` + `.glassEffectID(_:in:)`, and the filter change happens
  inside `withAnimation`.
- **No tint anywhere in `ios/Sources/Transactions/`.** `KanameApp.swift:10` already applies
  `.tint(.kanameAccent)` app-wide, so the app's accent is structural: a view in this directory
  that passes **any** `.tint(...)` is the only way the system default could come back, and none
  will. Debit/credit colour is **redundant** (the sign glyph and the a11y word are the carriers,
  FR-013/FR-071) and rows are never glassed, so the skill's "never a red/green amount on tinted
  glass" rule cannot be violated here.
- **Reduce Transparency / Increase Contrast** are handled by the native material substitution;
  nothing on this screen carries meaning through the material itself (FR-070). The filtered state
  is carried by **words** — the account's name in the scope button — never by the glass.
- **Order.** If any raw `.glassEffect(...)` is ever added, it goes **after** padding/frame/font.

**Deviations, recorded before building:**

- **D1 — Glass on an opaque bar refracts the bar, not content.** The skill says glass "needs
  content behind it to refract"; here there is deliberately nothing behind it. FR-068/FR-069
  outrank that guidance on this screen: the glass buys the native control treatment and touch
  response, not a material effect. Accepted as a deliberate trade, not an oversight.
- **D2 — `.buttonStyle(.glassProminent)` is permitted in exactly one state**: empty state 1
  ("nothing imported yet"), where the filter bar is absent (D3) and the import action is therefore
  the *only* glass element on screen. Every other empty state's action is `.buttonStyle(.glass)`,
  because the filter bar is on screen with it and two prominent elements make prominence
  meaningless. This narrows "exactly one glass element", it does not widen it.
- **D3 — The filter bar is hidden when `summaries.isEmpty`.** FR-038 ("the filtered account named
  at all times") is vacuous when there are no accounts and no filter can be set; a bar reading
  "All accounts" above a screen that says nothing was imported is a contradiction.
- **D4 / D5** — two model-shaped deviations, recorded under T047 as **E3** and **E4**.

---

#### T046 — The copy deck

Every sentence below is hand-written and belongs in `TransactionListStrings.swift` (T056). The
only engine-supplied strings that reach the screen are the **account name**, the **description as
printed**, and the **category name**. The masked last-4 is rendered through the app's own
`"•••• %@"` template — the same identity shape the front door already shows (FR-003) — never as
raw engine text. Dates and amounts are formatted by the app.

**Screen and navigation**

| Key | String |
|---|---|
| `title` | `Transactions` |
| `frontDoorLinkTitle` (N3 toolbar item) | `All transactions` |
| `loadingAnnouncement` | `Loading transactions` |

**Filter chrome** (FR-003, FR-038, FR-039)

| Key | String |
|---|---|
| `scopeAll` | `All accounts` |
| `scopeAccount(name:last4:)` | `<name>` with `•••• <last4>` beneath it; `<name>` alone when no last-4 |
| `menuHeader` | `Show transactions from` |
| `clearFilter` | `Show all accounts` |
| `scopeAccessibilityAll` | `Showing all accounts` |
| `scopeAccessibilityAccount` | `Showing <name>, ending <last4> only` — `Showing <name> only` without a last-4 |
| `scopeAccessibilityHint` | `Choose which account to show` |

**A row** (FR-012–FR-021)

| Key | String / shape |
|---|---|
| `directionWordDebit` | `debit` |
| `directionWordCredit` | `credit` |
| direction glyph on the amount | `−` (U+2212 MINUS SIGN) for a debit, `+` for a credit — **the** at-a-glance carrier, so colour is never the only one (FR-013). It is rendered from the recorded `Direction`, never from the sign of the amount (FR-014). |
| `uncategorized` | `Uncategorized` |
| `transferMarker` | `Transfer` (with `arrow.left.arrow.right`, so the marking is never colour alone) |
| `missingDescription` | `No description` — so an empty description still yields a complete, announceable row (FR-020) |
| `accountIdentity(name:last4:)` | `<name> ending <last4>` / `<name>` |
| `rowAccessibilityLabel` | **`<date>, <description>, <amount> <direction word>, <account identity>, <category>`**, plus `, transfer` when the flag is set. Example: `12 August 2026, Coffee shop, ₹450.00 debit, Example Bank Credit Card ending 1002, Uncategorized, transfer` |

⚠️ **Nothing here claims transfers are detected** (FR-018). The word is the bare noun `Transfer`
and the announcement is the bare `transfer` — never "detected", "found", "matched" or
"automatically". The app does not run detection today (research R18), and no string may imply
otherwise, in the UI, a test name or a release note.

**Date groups** (FR-026, FR-033–FR-035, FR-052, FR-072)

| Key | String |
|---|---|
| visible heading, current year | `12 August` |
| visible heading, any other year | `12 August 2025` |
| `groupAccessibilityLabel` | `12 August, 3 transactions` — singular `1 transaction` at one |

- **The visible heading carries no count and no figure.** FR-026 permits a count; leaving it off
  the *visible* heading keeps "a heading can never hold a sum" obvious at a glance.
- **The count moves to the heading's accessibility label**, where it is genuinely useful (it tells
  a VoiceOver reader how large the group is) and where it is unambiguously a count of
  transactions, not money. **This is the pluralisation helper's real, tested user** (FR-052,
  SC-013) — without it, the helper and its singular/plural test would be vacuous in this slice.
  The front door's existing count sentence (`ImportedAccountsView.announcement`) stays where it
  is: routing it through `TransactionListStrings` would breach H5's layering.
- The "current year" comes from the **injected clock** (V6), never `Date()` inside a formatter.

**The six empty states** (`data-model.md` §6 → FR-047–FR-052)

| # | Title | Message | Action |
|---|---|---|---|
| 1 | `Nothing imported yet` | `Import a statement and the transactions in it will appear here.` | `Import a statement` (D2: the one prominent button; wired to `RootView`'s existing picker, T099) |
| 2 | `No transactions` | `The statements you imported didn't have any transactions in them.` | — |
| 3 | `Nothing to show` | `There's nothing to show here yet. Import another statement to see transactions.` | `Import a statement` |
| 4 | `No transactions` | `The statement you imported for <name> didn't have any transactions in it.` | — |
| 5 | `Nothing to show` | `There's nothing to show for <name>.` | `Show all accounts` |
| 6 | `No transactions for <name>` | row 4's or row 5's sentence, followed by `Other accounts have transactions.` (see E3) | `Show all accounts` |

Wording rules these are written to satisfy, each asserted by a test rather than reviewed:

- **No empty-state string contains** `lost`, `missing`, `gone`, `error` or `failed` (FR-051).
  None of the six does. Row 4 is phrased as a fact about the statement, never as a failure, and
  never as "nothing imported yet" (FR-048).
- **No string contains an id, an internal code or a layer name** (FR-019, SC-016).
- **The only interpolations are** the account name and the masked last-4.

**The unavailable state** (H4, FR-063 — not an empty state)

| Key | String |
|---|---|
| `unavailableTitle` | `Transactions are unavailable` |
| `unavailableMessage` | `Kaname couldn't open your transactions just now. Everything is still stored on this device.` |
| `unavailableRetry` | `Try again` (see E4) |

No raw error text, no identifier, no description, amount, date or account crosses into it — the
`TransactionListError` it is rendered from carries none of those (H4).

---

#### T047 — The state-machine and empty-state trace

**Sufficiency — the question T047 exists to answer.** Every branch decides from
`[AccountSummary]` and `AccountFilter` alone:

```text
if summaries.isEmpty                                  -> 1  nothingImported
if filter == .account(id, name, last4):
    others = summaries.contains { $0.id != id && $0.liveTransactionCount > 0 }
    guard let mine = summaries.first(where: { $0.id == id }) else { -> E4 }
    if others  -> 6  accountEmptyOthersHaveRows(name, statementWasEmpty: !mine.hasOnlyExcludedRows)
    if mine.hasOnlyExcludedRows -> 5  accountNothingToShow(name)
    else                        -> 4  accountStatementEmpty(name)
else (.all):
    if summaries.contains(\.hasOnlyExcludedRows) -> 3  nothingToShowAnywhere
    else                                         -> 2  noTransactionsAnywhere
```

- **E6 — No field is missing.** Rows 4/5 need `hasOnlyExcludedRows`; row 6 needs
  `liveTransactionCount > 0` on *another* summary; rows 2/3 need `hasOnlyExcludedRows` across the
  set; naming needs `name` + `last4`. `AccountSummary` carries all of them, and **no count beyond
  `liveTransactionCount` is required** — so nothing here tempts a second population and FR-008
  holds structurally.
- **E7 — Rows 4–6 can never be confused with row 1.** Row 1 is `summaries.isEmpty`; rows 4–6 all
  require a filter over a non-empty `summaries`. The two conditions are mutually exclusive by
  construction, not by ordering.

**Findings raised (none required a change to a FINAL artifact):**

- **E1 — `data-model.md` §5's diagram says `empty (4 kinds)`; §6's table has six rows**, and both
  `contracts/platform-seams.md` V8 and T093 say six. **The table is authoritative — six cases.**
  The diagram's parenthetical is stale; recorded rather than edited.
- **E2 — `empty` and `unavailable` are drawn as terminal, and must not be.** Both must accept the
  same `filter changed` and `import completed` edges that `showing` accepts, or a person who lands
  on "Nothing imported yet", imports a statement, and stays stuck on it. Both edges re-enter
  `loading`. T058 implements it; the US7 suite pins it.
- **E3 (D4) — Row 6's precedence over rows 4–5 was ambiguous.** Read as *replaces*, FR-048's
  distinct "this statement had no transactions" state becomes nearly unreachable, since it would
  additionally require every *other* account to be empty — which inverts FR-048's intent. §6's own
  sentence resolves it: "row 6 **refines** rows 4–5 rather than replacing them". So case 6 keeps
  the account's own reason and *adds* the filter as a reason plus the clear action, carried as an
  associated **`statementWasEmpty: Bool`**. Still six cases, one per table row (T093 holds); the
  Bool is derived from `hasOnlyExcludedRows` and can never be rendered as a count.
- **E4 (D5) — A filter naming an account absent from `summaries` has no row in §6.** It is
  unreachable today (there is no delete path, and `data-model.md` §3 makes an unknown `account_id`
  an **empty page, not an error**), but the decision must be total. It resolves to **case 6** —
  named from the filter's own payload, with the clear action — when any other account has rows,
  and otherwise to case 2/3 with the clear action offered. No new field, no throw, no
  silently-cleared filter (which would breach FR-038's "named at all times").
- **E5 — `loadingMore` and `refreshing` in §5 are phases, not `State` cases.** The contract's enum
  is `.loading | .showing | .empty(EmptyKind) | .unavailable` with a separate `isLoadingMore: Bool`
  and a `refreshAfterImport()` that stays in `showing`. **T058 must not add enum cases for them** —
  a `.refreshing` case would make V3's "the filter and the anchor survive a refresh" a transition
  to prove rather than an invariant that cannot be broken.
- **E8 — `unavailable` had no outgoing edge at all.** `Try again` (T046) gives it one, re-entering
  `loading`. Nothing in the spec requires the action; a dead-end screen behind a transient store
  error is worse than one extra string, and it costs no new state.

**Checkpoint**: The visual contract, the copy and the state machine are fixed. UI may be built.

---

## Phase 3: User Story 1 — See everything I have, across every account (Priority: P1) 🎯 MVP

**Goal**: One combined list across every account, most recent first, each row carrying date, description, exact amount, direction and the account it belongs to — reachable in one action from the front door.

**Independent Test**: Import synthetic statements for two accounts with a known set of transactions each; open the combined list; confirm it shows exactly those transactions — same total count, same dates, same descriptions, same exact amounts, same directions, each attributed to the right account — as the fixtures declare, and that zero network requests occurred.

### Tests for User Story 1 (RED first) ⚠️

- [x] T048 [P] [US1] RED: create `ios/Tests/TransactionHistoryServiceTests.swift` (Swift Testing) — integration over the bridge against a temp SQLCipher store seeded with the correctness corpus: page 1's rows match the fixture exactly (date, description as printed, **exact `Decimal`** amount, recorded direction, currency, account name and last-4); concatenating every page equals the fixture's live rows and nothing else; a thrown `StoreError` becomes a `TransactionListError` carrying **no** description, amount, date or account identifier (H4).
- [x] T049 [P] [US1] RED: create `ios/Tests/TransactionListViewModelTests.swift` driven by an in-memory `TransactionHistoryReading` double — `onAppear` reaches `.showing` with the first screenful; V5 `loadMoreIfNeeded` is idempotent per cursor (two calls before the first returns issue one request); V7 `DateGroup` has no total, subtotal, balance or average member and no code path computes one; rows arrive in the engine's order and the view model re-sorts nothing (H2).
- [x] T050 [P] [US1] RED: create `ios/Tests/TransactionRowLayoutTests.swift` — A1 `amountYields == false` for **all twelve** `DynamicTypeSize` cases, iterating `DynamicTypeSize.allCases`; A2 `axis == .vertical` iff `dynamicTypeSize.isAccessibilitySize`; A3 `descriptionLineLimit` shrinks before `accountNameLineLimit` (the description yields first, the account name second, the amount never).
- [x] T051 [P] [US1] RED: create `ios/Tests/LivenessParityTests.swift` — against a store seeded with both deleted and superseded rows, `listTransactions(accountId:).filter(\.isLive).count` equals `accountSummaries()`'s `liveTransactionCount` for every account, and the id set of a full unfiltered `historyPage` walk equals the union of the `isLive` rows. This is the cross-language mirror of the engine's `LIVE` constant, and the reason `StoredTransaction.isLive` is retained rather than deleted.
- [x] T052 [US1] RED: widen the networking audit in `scripts/import-path-audit.sh` — point the `hits` and `import_hits` greps (`scripts/import-path-audit.sh:40–41`) at `$SOURCES_DIR` instead of `$IMPORT_DIR`, update the OK message to name `ios/Sources`, and prove it by dropping a temp file containing `URLSession` under `ios/Sources/Transactions/` and confirming `make import-audit` **fails**, then removing it. Today the glass and bank-literal scans cover all of `ios/Sources` and the networking scan does not, so a file at `ios/Sources/Transactions/TransactionHistoryService.swift` would ship with no networking audit at all (research R19, FR-062, SC-015). This lands in the same PR as the directory.

### Implementation for User Story 1

- [x] T053 [US1] Create `ios/Sources/Persistence/StoreProvider.swift`: `static func shared() throws -> Store` — **one `Store` per process**, memoised, opened through the existing `StoreLocator(keyStore: KeychainKeyStore())`, with an injection point so tests can hand in a temporary one. Two `Store` instances over one file would be two connections with two independent locks, and a page read could land inside `import_statement`'s transaction; one `Store` makes the engine's own mutex serialise reads against the atomic import, which is what makes FR-054 structural instead of timing-dependent.
- [x] T054 [US1] Rewire `ImportViewModel.liveService()` (`ios/Sources/Import/ImportViewModel.swift:47–51`) to take its store from `StoreProvider.shared()` rather than opening its own. Net line change ≤ 0; `ios/Sources/Import/ImportService.swift` is not touched.
- [x] T055 [P] [US1] Create `ios/Sources/Transactions/TransactionListModels.swift`: `TransactionRow` (mirroring `HistoryRow` plus the derived presentation facts as **pure functions** — `formattedAmount`, `directionWord`, `categoryLabel`, `accessibilityLabel`), `DateGroup` (`date`, `heading`, `rows` — **no amount member, and no member that could hold one**), `AccountFilter`, `EmptyKind`, `TransactionRowLayout` and `TransactionListError`.
- [x] T056 [P] [US1] Create `ios/Sources/Transactions/TransactionListStrings.swift` — every user-visible string of this slice, in one file, from the T046 copy deck. No string literal may appear in a view body; T112 asserts it.
- [x] T057 [P] [US1] Create `ios/Sources/Transactions/TransactionHistoryService.swift`: the `TransactionHistoryReading` protocol and the `actor TransactionHistoryService(store:)` with `page(accountID:cursor:limit:)` and `accountSummaries()`. An actor, so no engine call happens on the main thread (H1). A **transport**: no filtering, sorting, grouping, de-duplication or counting of its own (H2), no cache (H3), and `StoreError` mapped at the boundary (H4). It imports nothing from `Import/` (H5).
- [x] T058 [US1] Implement `TransactionListViewModel`'s paging in `ios/Sources/Transactions/TransactionListViewModel.swift`: `@MainActor @Observable`, `State` of `.loading | .showing | .empty(EmptyKind) | .unavailable`, page size 50, cursor held by the view model and nowhere else, `loadMoreIfNeeded(currentRowID:)` idempotent per cursor, every engine call awaited off the main actor.
- [x] T059 [US1] Implement **incremental** date grouping in `ios/Sources/Transactions/TransactionListViewModel.swift`: fold the flat page sequence into `[DateGroup]` as pages arrive, seeded with the open group's date, so a page boundary falling inside a date appends to the open group rather than starting a second group with the same heading. Extend `ios/Tests/TransactionListViewModelTests.swift` with V4 — page at size 1 across a 5-row date and assert exactly one group, and assert folding pages of 30 yields the same groups as folding the whole sequence at once (research R13).
- [x] T060 [US1] Implement `TransactionRowLayout(dynamicTypeSize:)` in `ios/Sources/Transactions/TransactionListModels.swift`: `.vertical` iff `dynamicTypeSize.isAccessibilitySize`, description line limit 2 horizontal / 3 vertical, account-name line limit 1, `amountYields` **always false**. Pure — no `View`, no environment, no rendering — so T050 can prove it with nothing on screen.
- [x] T061 [US1] Create `ios/Sources/Transactions/TransactionRowView.swift` driven by `TransactionRowLayout`: standard sizes an `HStack` (leading `VStack` of description then account name, trailing amount), accessibility sizes a single `VStack` with the amount last and full width. The amount takes `.fixedSize(horizontal: true, vertical: false)`, `.layoutPriority(1)` and `.monospacedDigit()`; **never** `minimumScaleFactor`, never `.truncationMode`, never an abbreviation. **Not `LabeledContent`** — it chooses its own axis and renders its value `.secondary`, which is the exact shape the parked `StaticText '1'` at `{32, 724}` occlusion finding is consistent with (research R12, A4). One `.accessibilityElement(children: .combine)` per row with the T055 sentence as its label.
- [x] T062 [US1] Create `ios/Sources/Transactions/TransactionListView.swift`: a `List` of `Section`s with `.listStyle(.plain)` so headings pin while scrolling (FR-034), rows on an **opaque** surface with no material and no glass anywhere near them, and the whole screen inside the existing `NavigationStack`. Direction is carried by a word and a glyph, never by colour alone (W5).
- [x] T063 [US1] Add the destination to `ios/Sources/RootView.swift`: one `NavigationStack` destination for the list — not a sheet, not a tab (a sheet's dismissal is not the standard back affordance and makes FR-056's scroll preservation a dismissal problem) — plus a toolbar item that pushes the **unfiltered** list, so the combined history is reachable without picking an account first (FR-001, N3). Switch `RootView.swift:15`'s `.safeAreaInset(edge: .bottom)` to `.safeAreaBar(edge: .bottom)` (W3, verified present in the iOS 26.5 SDK).
- [x] T064 [US1] Make each row of `ios/Sources/Import/ImportedAccountsView.swift` a `NavigationLink` pushing the list pre-filtered to that account, carrying the **same `AccountFilter` value** the in-screen filter will set — one code path, not two (N2, FR-037). Back returns to the front door with its state intact (FR-005).
- [x] T065 [US1] Replace the `LabeledContent` in `ios/Sources/Import/ImportedAccountsView.swift:10` with the same explicit two-column shape `TransactionRowView` uses, so the front door stops being the layout the parked occlusion finding is about. The file is already being edited by T064; this is the small in-scope change research R12 calls for, and it removes the `.foregroundStyle(.primary)` override that only existed to fight the component.
- [x] T066 [US1] Give `ImportedAccount` a `hasOnlyExcludedRows: Bool` in `ios/Sources/Import/ImportModels.swift` (fed from `AccountSummary`), and update `StoredTransaction.isLive`'s ⚠️ comment (`ImportModels.swift:79–89`): it is **no longer the production count** — it is the cross-language mirror of the engine's `LIVE` constant, pinned by `ios/Tests/LivenessParityTests.swift`.
- [x] T067 [US1] ⚠️ Switch the front-door count to the engine in `ios/Sources/Import/ImportService.swift:128–141`: replace the per-account `store.listTransactions(accountId:).filter(\.isLive).count` with one `store.accountSummaries()` call mapped to `[ImportedAccount]`. This **removes** lines from a file at exactly the 400-line SwiftLint limit — record the new `wc -l` in the PR description, because T137 spends that headroom. Measured on the 10,000-row corpus: 43.8 ms of Rust time becomes 0.99 ms, and the only place where the count and the list could be computed by different code disappears (FR-006, FR-008).
- [x] T068 [US1] **GATE** `make lint` — `swiftlint --strict` (400-line files, 120 columns) + `swift-format lint --strict`. Confirm `wc -l ios/Sources/Import/ImportService.swift` ≤ 400.
- [ ] T069 [US1] **GATE** `make ios-gen && make ios-test` — T048–T051 green. Never a bare `tuist generate`. ⚠️ **BLOCKED, and not by this slice** — see the US1 note below: the unit target is green (166 tests, 37 suites), the UI target is red on **unmodified `main`** for a front-door contrast failure that predates PR B.
- [x] T070 [US1] **GATE** `make import-audit` — with the widened networking scan now covering `ios/Sources/Transactions/`, plus the unchanged glass, `#available(iOS 26` and bank-literal scans (SC-015, FR-062).

**Checkpoint**: 🎯 **MVP.** A person can open the app, tap once, and read their own transactions across every account. Shippable on its own.

### US1 — RECORDED: what was built, what deviated, and the one gate that is red

**Green:** `make lint` (0 violations, swiftlint --strict + swift-format --strict), `make
import-audit` (all four scans, networking now over all of `ios/Sources`), and the **unit target
— 166 tests in 37 suites**, T048–T051 included. `ios/Sources/Import/ImportService.swift` is
**397 lines**, three below the limit it sat exactly on (T067's headroom for T137).

**RED was observed before GREEN.** The four new suites failed to compile against `main` —
`cannot find type 'TransactionHistoryService' in scope`, `cannot find type
'TransactionHistoryReading' in scope`. In Swift that is what RED looks like for a new seam:
the test names the type that does not exist yet, and the target does not build until it does.

⚠️ **T069 is blocked by a failure that predates this PR.** `make ios-test` runs the UI target
too, and `ImportFrontDoorUITests.testTheFrontDoorPassesTheAuditInDarkModeAtTheLargestTextSize`
fails with `Contrast failed` on the front door's explanation text. **Verified pre-existing**:
stashed to a clean `main`, regenerated, ran that one test — it fails identically, with the same
element at the same frame `{{24, 467}, {345, 621.3}}`. It was green when it was written
(`ebfbcf0`), so an SDK or simulator-runtime change is the likeliest cause.

What the evidence says: at the largest accessibility size the explanation is 621 pt tall on an
852 pt screen, so it scrolls under the bottom bar, and the soft scroll-edge effect renders the
lines passing behind the bar at a reduced contrast the auditor measures and fails. Two fixes
were tried against it and **both reverted**, because neither worked and this is not this
slice's screen:

- `.safeAreaInset(edge: .bottom)` → `.safeAreaBar(edge: .bottom)` on `ImportEmptyStateView`:
  no change; the reported element frame was byte-identical before and after.
- `.scrollEdgeEffectStyle(.hard, for: .bottom)`: made it **worse** — the light-mode largest-size
  case (`testTheFrontDoorSurvivesTheLargestAccessibilityTextSize`) went red too.

It belongs to whoever owns the front door's accessibility next, with 016's manual gate. **It is
recorded rather than papered over, and T069 stays unchecked until it is settled** — a gate
marked green while red is worth less than no gate.

**Deviations from `tasks.md`, each deliberate:**

- **A fifth test file.** `ios/Tests/TransactionCorpus.swift` — the platform half of the
  correctness corpus, shared by T048 and T051. The alternative was the same 200-line fixture
  duplicated in two files, which is how two fixtures come to disagree about what they are
  fixtures of.
- **The corpus cannot build a deleted row, and says so.** `is_deleted` has no write path in the
  store's API; the Rust corpus reaches it with direct SQL through SQLCipher, which Swift has no
  handle on. `LivenessParityTests` therefore proves the **superseded** half of the live rule end
  to end and names the gap in its own doc comment; the `!isDeleted` half stays pinned engine-side
  (`history_live.rs` L1–L5 and the `LIVE` byte-identity assertion). No test pretends otherwise.
- **US7's empty states landed early** — `EmptyKind.decide` (T096) and the rendering (T098). US1's
  checkpoint claims the slice is shippable on its own, and a screen that goes blank when a
  person has nothing imported is not shippable. The T047 trace had already settled every branch,
  so the code was the small part. ⚠️ **Consequence to honour**: T093's RED suite will be written
  against code that already exists. Write it anyway, and **observe it fail** by breaking the
  decision on purpose (swap two cases, delete the `hasOnlyExcludedRows` branch) before trusting
  it — a suite that has only ever been green proves nothing about what it would catch.
- **`refreshAfterImport()` is not implemented.** The contract lists it, but its story (staying
  current with an import) is a later phase, and an untested method on a shipped view model is
  worse than an absent one.
- **The row carries no colour for direction.** The sign glyph (`−` / `+`) and the spoken word
  carry it, per the T046 deck, which lists colour as redundant and optional. Adding a red/green
  amount would add a contrast axis to the manual gate for no information a person does not
  already have.

## Phase 4: User Story 2 — Re-importing a statement does not double what the person sees (Priority: P2)

**Goal**: The live-row rule holds end to end. A re-import changes nothing a person can see, and the front-door count and the filtered list can never disagree.

**Independent Test**: Import one synthetic statement, record the list's rows and their order; import the identical file again; confirm contents, count and order are unchanged, and that every front-door count still equals the number of rows the list shows when filtered to that account.

### Tests for User Story 2 (RED first) ⚠️

- [x] T071 [P] [US2] RED: create `ios/Tests/TransactionListLivenessTests.swift` — over the bridge against a real temp store: importing the identical statement twice leaves the rendered row ids, their count and their order identical (FR-009, SC-003); a superseded row and a deleted row appear nowhere, in any filter state (FR-007, SC-005); an excluded row leaves **no gap, no blank row, no placeholder and no effect on grouping** — the `DateGroup` sequence is byte-identical to a store that never held the excluded rows (FR-010).
- [x] T072 [P] [US2] RED: add `frontDoorCountEqualsTheFilteredRowCountInEveryState` to `ios/Tests/TransactionListLivenessTests.swift`, asserting the equality after a first import, after a re-import that supersedes duplicates, and after a deletion — the states SC-004 names (FR-006, FR-046).

### Implementation for User Story 2

- [x] T073 [US2] Confirm — and pin, do not add — that nothing in `ios/Sources/Transactions/` re-derives the population: `TransactionHistoryService` is transport-only, `TransactionListViewModel` never filters `rows`, and the count on the front door comes from `AccountSummary.liveTransactionCount` alone. Any Swift-side `.filter` over transactions found on this path is deleted here (FR-008, FR-045).
- [x] T074 [US2] Ensure an import affecting one account cannot disturb another in `ios/Sources/Transactions/TransactionListViewModel.swift`: a refresh re-reads through the engine rather than mutating rows in place, so per-account state cannot drift (FR-011). Extend `ios/Tests/TransactionListLivenessTests.swift` with the assertion.
- [x] T075 [US2] **GATE** `make lint && make ios-test` — T071 and T072 green. Run as `make lint`, `make import-audit` and `-only-testing:KanameTests` (**172 tests in 38 suites**, all green); the UI target is still red for the front-door contrast failure that predates this slice (see T069).

**Checkpoint**: The screen that doubled a person's history in 016 cannot do it again, and the count and the list are provably one definition.

### US2 — RECORDED

**Every assertion was observed failing before it was trusted.** The implementation US2 needed
already existed — US1 built it — so a suite written here would otherwise have been green from
birth and proved nothing. Three deliberate breaks, each reverted:

1. **The 016 defect, put back**: `importedAccounts()` counting `listTransactions(…).count`
   instead of `liveTransactionCount`. T072 went red with the exact shape of the original bug —
   *the front door says 8, the list shows 4*.
2. **A second Swift-side population**: a `TransactionHistoryReading` that assembled pages from
   the raw `listTransactions`. Five of the six tests went red, including every superseded row
   becoming visible and the two stores' `DateGroup` sequences diverging.
3. **A refresh that mutates in place**: `reload()` no longer clearing `groups`. T074 went red —
   and only after it was rewritten to drive **one** screen across the import. Its first form
   opened a fresh view model each time and stayed green under this break, which is the whole
   reason the break was run.

**Deviations, each deliberate:**

- **The deletion state is unreachable from Swift, and stays pinned engine-side.** SC-004 names
  "after a deletion", but `is_deleted` has no write path in the store's API — the Rust corpus
  reaches it with direct SQL through SQLCipher, which Swift has no handle on. T072 therefore
  asserts the count equality over the three states a real install can actually reach — a first
  import, a re-import that supersedes its own duplicates, and cross-source duplicates linked by
  `findDuplicates()` — and the deleted row stays covered by `history_live.rs` L1 (visibility)
  and L4/L5 (counts). The suite says so in its own doc comment, and asserts `!isDeleted` over
  the corpus so a future write path cannot slip past untested. Same gap US1 recorded, named
  once more where it bites.
- **T073 found nothing to delete, so it pinned instead.** Nothing under
  `ios/Sources/Transactions/` re-derives the population today. A confirmation that lives only in
  a commit message is not a pin, so `scripts/import-path-audit.sh` grew a fourth scan: no
  `listTransactions(` call anywhere under `ios/Sources`, and no `isLive`, `supersededBy`,
  `isDeleted`, `rows.filter`/`rows.sorted` or `groups.filter`/`groups.sorted` under
  `ios/Sources/Transactions/`. Both directions were verified — the scan was watched failing
  against a deliberately reintroduced raw count.
- **Two stores, not one, prove FR-010.** "No trace" is compared against a store that never held
  an excluded row, over a projection that leaves row ids out — ids cannot match across stores,
  and a comparison that passed because of them would prove nothing. Ids are compared directly
  where they are meaningful: within one store, across a re-import.

## Phase 5: User Story 4 — A long history reads as a history, not a pile (Priority: P4)

**Goal**: Most-recent-first across accounts, grouped by date with the current date always identifiable, and an order that is identical across launches and unchanged by a further import.

**Independent Test**: Import several synthetic statements for at least three accounts over multiple months, including a day carrying rows from more than one account; confirm the list is newest-first, grouped and headed by date, the heading stays identifiable while scrolling, and the exact order — including same-date rows from different accounts — is identical across a relaunch and again after importing an unrelated account.

### Tests for User Story 4 (RED first) ⚠️

- [x] T076 [P] [US4] RED: create `ios/Tests/TransactionListOrderingTests.swift` — the rendered sequence is newest-first across accounts; same-date rows of different accounts appear in front-door account order; same-date rows of one account appear in printed order; rebuilding the view model from a fresh service over an unchanged store yields a byte-identical sequence (the app-side mirror of O5, SC-009); importing a further account leaves the relative order of every pre-existing row unchanged (FR-032).
- [x] T077 [P] [US4] RED: add the heading tests to `ios/Tests/TransactionListViewModelTests.swift` — V6 the year suffix comes from the **injected clock**, never `Date()` inside a formatter, so "include the year when it is not the current year" (FR-035) is assertable at a fixed date; one group per calendar date **across all accounts**, never one group per account per date (FR-033); every heading carries the date and at most a transaction **count**, never a monetary aggregate (FR-026).

### Implementation for User Story 4

- [x] T078 [US4] **Already landed in US1 — confirmed, not re-implemented.** Implement the injected clock in `ios/Sources/Transactions/TransactionListViewModel.swift` (`init(history:clock:pageSize:)`, defaulting to `Date.init`) and derive each `DateGroup.heading` from it in `ios/Sources/Transactions/TransactionListModels.swift` — the same pattern `ImportService`'s `now:` parameter already uses, and the reason the core reads no wall clock (Constitution II).
- [x] T079 [US4] Render group headings in `ios/Sources/Transactions/TransactionListView.swift` as `Section` headers on a plain `List`, so the system pins them while scrolling and the date currently being read stays identifiable (FR-034), and so the heading is announced when its group is entered (FR-072).
- [x] T080 [US4] Confirm the ordering is expressed in exactly two places and nowhere else: the engine's SQL + comparator, and `data-model.md` §2. Grep `ios/Sources/Transactions/` for `sorted`, `sort(`, `reversed` and assert none applies to transaction rows — the app renders the sequence it was given (FR-045).
- [x] T081 [US4] Handle the row edges from the spec in `ios/Sources/Transactions/TransactionRowView.swift`: an empty or unreadable description still renders a complete, selectable, announceable row carrying date, account and amount (FR-020); a very long description or account name yields before the amount, which never yields (FR-021). Add both to `ios/Tests/TransactionRowLayoutTests.swift`.
- [x] T082 [US4] **GATE** `make lint && make ios-test` — T076, T077 and T081 green. Run as `make lint` (0 violations) + `-only-testing:KanameTests`: **185 tests in 40 suites**. The UI target stays red for the pre-existing front-door contrast failure (T069).
- [x] T083 [US4] **GATE** `make core-lint && make core-test && make import-audit` — the full PR B verification gate, engine included, before the PR opens. Green: clippy clean, **308 core tests** across 16 binaries, all five audit scans.

**Checkpoint**: US1, US2 and US4 are independently functional. The list is demoable, ordered, stable and honest about what it holds.

### US4 — RECORDED

**T078, T079 and T081's implementation had already landed in US1** — the injected clock, the
`Section` headings on a `.plain` list, and the row's yield order were all built there. US4 was
therefore mostly *proving* them, which makes the red observations the substance of this phase,
not a formality. **Five deliberate breaks, each reverted, each watched:**

1. **A re-sorted page** (`page.rows.sorted(by: amount)`): 5 of the 7 ordering tests red.
2. **A shuffled page**: the determinism test red — two reads of one unchanged store disagreeing
   is exactly the failure SC-009 exists to forbid.
3. **The clock ignored** (`Date()` instead of `clock()`): the year-suffix test red. This is the
   defect that is right for 364 days a year, and it cannot be caught any other way.
4. **The grouping key widened to `(date, account)`**: the one-group-per-date test red, with
   three headings where a person should see one.
5. **A total appended to the heading**: the no-figure test red on both the heading and its
   VoiceOver announcement.

**Deviations, each deliberate:**

- **The fixture was rebuilt mid-phase, because it was too weak to fail.** The first version's
  printed order happened to coincide with descending amount, so break 1 slipped past the
  printed-order test. The shared date now carries **three** rows of one account —
  `MEDLAR 01, ALMOND 02, ZEBRA 03` at 500 / 900 / 100 — an order that matches neither
  alphabetical direction, neither amount direction, nor reversed insertion. A fixture that
  cannot distinguish printed order from a sort proves nothing about printed order.
- **The account tie-break is proved by non-vacuity, not by a code break.** That rule lives in
  the engine's SQL (`history_order.rs` O2 owns it); the app-side claim is that appearance order
  *equals* `listAccounts()` order. It was verified by asserting the **reverse** and watching it
  fail — the fixture's three accounts on one date really do come back in front-door order.
- **The ordering fixture is written through `insertAccount`/`insertTransaction`, not a parsed
  statement.** The ordering key's third component is `rowid`, and only direct inserts let a test
  say exactly which row follows which. What the *import* path does to the order is already
  covered end to end by US2's suite.
- **T080 pinned rather than only confirmed.** No `sorted`, `sort(` or `reversed` exists under
  `ios/Sources/Transactions/`, so the audit's fifth scan now bans all three there — the order is
  written down in the engine's SQL and in `data-model.md` §2, and a third copy fails the build.
  Watched failing against a deliberately reversed page.
- **Two test files were split out, because the view model's suite outgrew its limits.** Adding
  T077 pushed `TransactionListViewModelTests.swift` past both the 400-line file limit and the
  250-line type-body limit. The shared double and fixtures moved to
  `ios/Tests/TransactionListDoubles.swift` (one copy, so two suites cannot come to disagree
  about what they are fixtures of), and the heading tests to
  `ios/Tests/TransactionListHeadingTests.swift`. No assertion was lost or weakened in the move.

---

# PR C — Filter and honesty

*The account filter, the six empty states, pluralisation, and the "no blame words" test. **US3, US7.***

## Phase 6: User Story 3 — Narrow to one account (Priority: P3)

**Goal**: The same list with fewer rows in it — named on screen at all times, clearable in one action, changeable without leaving the screen, and never persisted across launches.

**Independent Test**: Import synthetic statements for three accounts; tap one on the front door; confirm the list shows exactly that account's live transactions and exactly the count the front door showed; clear the filter in one action and confirm all three accounts return; re-apply, relaunch, and confirm the list is unfiltered.

### Tests for User Story 3 (RED first) ⚠️

- [ ] T084 [P] [US3] RED: create `ios/Tests/TransactionFilterTests.swift` — V1 `filter` is `.all` at `init` and a filter change writes **nothing** to `UserDefaults` (assert the suite's `UserDefaults` dictionary is byte-identical across a `setFilter`), nothing to the store, and nothing to a scene-restoration payload; a fresh view model after a simulated relaunch is `.all` (FR-041).
- [ ] T085 [P] [US3] RED: add the population tests to `ios/Tests/TransactionFilterTests.swift` — V2 `setFilter`/`clearFilter` discard the cursor and **every** accumulated row before loading page 1, so no row of the previous account can survive (FR-040); a filtered list's row count equals the front-door count for that account (FR-006); filtering changes no ordering, no grouping, no row content and no currency handling — a filtered sequence is the unfiltered sequence with the other accounts removed (FR-042).
- [ ] T086 [P] [US3] RED: add the announcement tests to `ios/Tests/TransactionFilterTests.swift` — the filtered account's name (and last-4, matching the front door's identity) is present in the screen's accessibility surface whenever a filter is applied, and the fact that the list is filtered is carried by a **string**, never by styling alone (FR-038, FR-003, SC-014).

### Implementation for User Story 3

- [ ] T087 [US3] Implement `setFilter(_:)` and `clearFilter()` in `ios/Sources/Transactions/TransactionListViewModel.swift`: discard cursor and rows, reload page 1 with `HistoryQuery.accountId` set or `nil`. That single field is the **only** difference between a filtered and an unfiltered read (FR-036, FR-042).
- [ ] T088 [US3] Build the filter chrome in `ios/Sources/Transactions/TransactionListView.swift`: a `Menu`/picker of accounts plus the current scope, in a `GlassEffectContainer` with `.buttonStyle(.glass)`, pinned by `.safeAreaBar(edge: .bottom)` on an **opaque** bar. Glass never touches the rows, and a prominent translucent control never refracts scrolled numbers (FR-068, FR-069, W1, W3).
- [ ] T089 [US3] Make the current scope unmistakable at all times in `ios/Sources/Transactions/TransactionListView.swift` — either "All accounts" or the filtered account's name and masked last-4, using the same identity the front door shows, visible without scrolling (FR-003, FR-038).
- [ ] T090 [US3] Make clearing a **single** action and changing the filter possible without leaving the screen, in `ios/Sources/Transactions/TransactionListView.swift` (FR-039, FR-040).
- [ ] T091 [US3] Confirm the front-door `NavigationLink` from T064 sets the same `AccountFilter` value the in-screen picker sets, in `ios/Sources/Import/ImportedAccountsView.swift` — one code path for a pre-filter and a chosen filter (N2).
- [ ] T092 [US3] **GATE** `make lint && make ios-test` — T084–T086 green.

## Phase 7: User Story 7 — Nothing to show says why (Priority: P7)

**Goal**: Six distinct, plainly-worded empty states that tell an unimported store, a genuinely empty statement, an all-excluded account and a filtered-to-nothing account apart — and never suggest data was lost.

**Independent Test**: Produce the four states — nothing imported; a statement that genuinely parsed zero transactions; an account whose every row is superseded or deleted; the filter applied to an account with nothing live while others have rows — and confirm each shows a distinct sentence that does not accuse the app of losing anything.

### Tests for User Story 7 (RED first) ⚠️

- [ ] T093 [P] [US7] RED: create `ios/Tests/TransactionEmptyStateTests.swift` — V8 `EmptyKind` is a **pure function** of `[AccountSummary]` and `AccountFilter`, and each of the six rows of `data-model.md` §6 maps to its own case: empty summaries → "nothing imported yet" + the import action; all-zero with none excluded → "the statements had no transactions"; all-zero with some excluded → "nothing to show"; filtered, zero, not excluded → "this statement had no transactions" (**not** an error, **not** "nothing imported"); filtered, zero, excluded → "nothing to show for this account" + clear-the-filter; filtered to zero while other accounts have rows → the filter named as the reason + clear-the-filter.
- [ ] T094 [P] [US7] RED: create `ios/Tests/TransactionListStringsTests.swift` — every worded count is produced by **one** pluralisation helper, asserted singular for `1` and plural for `0` and `2` in every string that carries a count (FR-052, SC-013).
- [ ] T095 [P] [US7] RED: add the honesty audits to `ios/Tests/TransactionListStringsTests.swift` — no empty-state string contains "lost", "missing", "gone", "error" or "failed" (FR-051); no user-visible string in `TransactionListStrings` contains an identifier, an internal code, a dedup layer name, a cursor field name (`sequence`) or engine error text (FR-019, SC-016).

### Implementation for User Story 7

- [ ] T096 [US7] Implement the `EmptyKind` decision as a pure function over `[AccountSummary]` and `AccountFilter` in `ios/Sources/Transactions/TransactionListModels.swift`, following `data-model.md` §6 row for row. `hasOnlyExcludedRows` is what tells row 4 from row 5 — and it is a bool precisely so it can never be rendered as a count (FR-008).
- [ ] T097 [US7] Implement the pluralisation helper in `ios/Sources/Transactions/TransactionListStrings.swift` — one helper, used by every worded count in the slice, including the front door's row announcement if it words one (FR-052).
- [ ] T098 [US7] Render the six empty states in `ios/Sources/Transactions/TransactionListView.swift` using `ContentUnavailableView` with the T046 copy: the unimported state offers the import action (FR-047), and every filtered state that would show something once cleared offers to clear the filter (FR-049).
- [ ] T099 [US7] Wire the empty state's import action back to `RootView`'s existing `.fileImporter` in `ios/Sources/RootView.swift` — no second picker, no duplicated import path (FR-047).
- [ ] T100 [US7] Render `.unavailable` (a store error) in `ios/Sources/Transactions/TransactionListView.swift` with a plain-language sentence carrying **no** engine text, no error code and no identifier (FR-019, H4).
- [ ] T101 [US7] **GATE** `make lint && make ios-test` — T093–T095 green.
- [ ] T102 [US7] **GATE** `make core-lint && make core-test && make import-audit` — the full PR C verification gate before the PR opens.

**Checkpoint**: The list narrows to one account, names its scope, clears in one action, forgets the filter on relaunch, and every empty screen says why without blaming anyone.

---

# PR D — What the engine already knows

*Per-row currency formatting, category names, transfer marking, and the full VoiceOver / Dynamic Type / contrast suite. **US5, US6.***

## Phase 8: User Story 5 — Two currencies never quietly become one (Priority: P5)

**Goal**: Every amount carries its own currency, always; nothing is converted; and no figure anywhere in this feature is derived from amounts of more than one currency.

**Independent Test**: Import synthetic statements for two accounts in different currencies, including both currencies on the same date; confirm every row carries its own currency unambiguously, no conversion appears, and no figure aggregates across currencies.

### Tests for User Story 5 (RED first) ⚠️

- [ ] T103 [P] [US5] RED: create `ios/Tests/TransactionAmountTests.swift` — `formattedAmount` uses `Decimal.formatted(.currency(code:))` and round-trips a 7-integer-digit, 2-decimal amount with **zero** drift; the currency code comes from the **transaction's** `currency`, never the account's and never the locale's; a currency `en_IN` does not localise still renders exactly and unambiguously (FR-027); the amount is never abbreviated, scaled or truncated.
- [ ] T104 [P] [US5] RED: add the no-aggregate audit to `ios/Tests/TransactionAmountTests.swift` — grep the compiled model surface and `ios/Sources/Transactions/` for `reduce`, `sum`, `total`, `average`, `balance` applied to an amount and assert none exists; assert `DateGroup` exposes no numeric member other than a row count (FR-025, FR-026, SC-011).
- [ ] T105 [P] [US5] RED: add `theAccessibilityLabelAnnouncesTheCurrencyWithTheAmount` to `ios/Tests/TransactionAmountTests.swift` (FR-015, US5 AS-5).

### Implementation for User Story 5

- [ ] T106 [US5] Implement `formattedAmount` in `ios/Sources/Transactions/TransactionListModels.swift` with `Decimal.formatted(.currency(code:))` — `Decimal`'s own `FormatStyle`, which never routes through `Double`. No `NumberFormatter` with a `Double` input, no `String(format:)`, no `Double` anywhere on the path (Constitution II, FR-016).
- [ ] T107 [US5] Apply `.monospacedDigit()` to every amount and every count rendered by `ios/Sources/Transactions/TransactionRowView.swift` and `TransactionListView.swift`, so figures do not jitter while scrolling (FR-016, FR-027).
- [ ] T108 [US5] Include the currency in the row's accessibility sentence in `ios/Sources/Transactions/TransactionListModels.swift`, alongside date, description, amount, direction in words and account (FR-015).
- [ ] T109 [US5] **GATE** `make lint && make ios-test` — T103–T105 green.

## Phase 9: User Story 6 — What the engine already worked out is visible (Priority: P6)

**Goal**: Categories shown by name, uncategorized labelled in plain language, transfers marked by more than colour and announced — and **no** claim, anywhere, that the app detects transfers.

**Independent Test**: Seed a store containing categorized and uncategorized transactions plus a transfer pair whose flag the **test** sets; confirm both sides are marked and announced, categories are shown by name, and uncategorized rows say so rather than showing a blank.

> ⚠️ **`detectTransfers()` is called from no Swift source file, and this slice does not wire it** (research R18, FR-018). `is_transfer` is `0` on every row in a real install. Tests set the flag themselves — `store.detectTransfers()` inside the test, exactly as `ios/Tests/StoreTransferTests.swift:69` already does, or by seeding the column directly. **No task, test name, string or release note may imply the app detects transfers.** Wiring is the categorize slice's work.

### Tests for User Story 6 (RED first) ⚠️

- [ ] T110 [P] [US6] RED: create `ios/Tests/TransactionCategoryTests.swift` — a categorized row shows its category **by name**; an uncategorized row shows the plain-language label rather than a blank (FR-017); no row surfaces a `category_id`, a `categorised_by`, a dedup layer name or any other engine internal (FR-019, SC-016).
- [ ] T111 [P] [US6] RED: create `ios/Tests/TransactionTransferMarkingTests.swift` — with the flag set **by the test**, a flagged row renders the transfer marking; the marking is carried by a glyph **and** a word, never by colour alone (FR-018, FR-071); the accessibility sentence announces it; the row **still appears** in the list and is never hidden or filtered out (US6 AS-7); with the flag unset, no marking appears. Name every test for the **marking**, never for detection.
- [ ] T112 [P] [US6] RED: create `ios/Tests/TransactionAccessibilityTests.swift` — the automatable half of SC-013: each row is one combined element whose label is the exact expected sentence (date, description, amount with currency, direction in words, account, and "transfer" when marked); every date heading has a label; direction, transfer, uncategorized and the filtered state are each identifiable **with colour perception removed entirely** (FR-071, SC-014); no view body contains a user-visible string literal — every one comes from `TransactionListStrings` (W4).

### Implementation for User Story 6

- [ ] T113 [US6] Implement `categoryLabel` as `categoryName ?? Strings.uncategorized` in `ios/Sources/Transactions/TransactionListModels.swift` — never blank, never an identifier (FR-017).
- [ ] T114 [US6] Render the category and the transfer marking in `ios/Sources/Transactions/TransactionRowView.swift` as an SF Symbol **plus** its word, sized so both survive the accessibility text sizes and the vertical layout, and never encoded in colour (FR-018, FR-071).
- [ ] T115 [US6] Compose the full row accessibility sentence in `ios/Sources/Transactions/TransactionListModels.swift` and assert nothing else on the row is separately focusable (FR-015, FR-072).
- [ ] T116 [US6] Restore full contrast explicitly wherever a container would render content in a de-emphasised style across `ios/Sources/Transactions/` — the account name, the category and the date are **content**, not decoration (FR-066). This is the failure 016 paid for at four sites; it is a requirement here, not a preference.
- [ ] T117 [US6] Confirm every tint on this screen is the app's own accent from `ios/Sources/Theme.swift`, never the system default, across `ios/Sources/Transactions/` (FR-073).
- [ ] T118 [US6] Extend `ios/UITests/ImportFrontDoorUITests.swift` with `theEmptyTransactionListPassesTheSystemAccessibilityAudit`: from a fresh install, push the unfiltered list via the toolbar item and run `performAccessibilityAudit()` at default and at the largest accessibility text size, in Light and Dark Mode. **This is the only part of the screen an automated audit can reach** — the populated list sits behind a real file being picked, which no automated run can do, and FR-077 forbids adding a DEBUG-only seeding hook to close that gap here. The populated screen stays on the manual gate (SC-012, FR-075, FR-076).
- [ ] T119 [US6] Audit mechanically that detection stays unwired: add a check to `scripts/import-path-audit.sh` (or a Swift test in `ios/Tests/TransactionTransferMarkingTests.swift`) failing if `detectTransfers` appears anywhere under `ios/Sources/`, and grep `ios/Tests/` and this file for a test or task name implying detection. FR-018's limitation must be impossible to lose by accident.
- [ ] T120 [US6] **GATE** `make lint && make ios-test` — T110–T112 green, including the new UI test.
- [ ] T121 [US6] **GATE** `make core-lint && make core-test && make import-audit` — the full PR D verification gate before the PR opens.

**Checkpoint**: Every field the engine already holds is on screen, announced, and never encoded in colour alone — and the transfer marking is honest about being unexercised in a real install.

---

# PR E — Live and fast

*The import-completion signal, scroll-anchor capture and restore, the perf gates, the manual gate record, and the documentation updates. **US8** + Polish.*

## Phase 10: User Story 8 — The list keeps up with an import, and stays honest during one (Priority: P8)

**Goal**: A completed import appears without a relaunch, as one complete change; a failed or cancelled one changes nothing; and neither the filter nor the scroll position is taken away from the person.

**Independent Test**: With the list open, import a further synthetic statement; confirm the new transactions appear on completion with no relaunch, that no partially-written state was visible, and that a cancelled import leaves the list identical — tested both unfiltered and filtered to an account the import does not touch.

### Tests for User Story 8 (RED first) ⚠️

- [ ] T122 [P] [US8] RED: create `ios/Tests/ImportCompletionSignalTests.swift` — I1 the signal is emitted **after** `import_statement` returns successfully, so a subscriber can never observe a partial statement; I2 a failed or cancelled import emits **nothing** (FR-055); I3 it carries `Void` — no row, count or account crosses it, so there is still exactly one source of the population; I4 the subscription dies with the screen's `.task`.
- [ ] T123 [P] [US8] RED: add the refresh invariants to `ios/Tests/TransactionFilterTests.swift` — V3 `refreshAfterImport` preserves `filter` **and** the captured anchor row id (FR-056, SC-010); a refresh while filtered to an account the import did not touch leaves the rendered sequence byte-identical (US8 AS-6); a refresh never re-requests a cursor it has already consumed, so no row is duplicated.
- [ ] T124 [P] [US8] RED: add `aCancelledImportProducesNoTransitionAtAll` to `ios/Tests/ImportCompletionSignalTests.swift` — the view model's state sequence across a cancelled import is empty, because no event is emitted (`data-model.md` §5 invariant 5).

### Implementation for User Story 8

- [ ] T125 [US8] ⚠️ Create `ios/Sources/Transactions/ImportCompletionSignal.swift` holding the `AsyncStream<Void>` continuation store, and add the **minimum** plumbing to `ios/Sources/Import/ImportService.swift` to yield it on the success path only — spending the headroom T067 created. **Re-check `wc -l ios/Sources/Import/ImportService.swift` ≤ 400 before and after** and record both numbers; if the file would exceed 400, move something out rather than reformatting to squeeze under (`swiftlint --strict`).
- [ ] T126 [US8] Implement `refreshAfterImport()` in `ios/Sources/Transactions/TransactionListViewModel.swift`: re-read the pages currently held, from page 1, with the **same filter**, and swap them in as one change so the list never trickles (FR-053, FR-054).
- [ ] T127 [US8] Implement anchor capture and restore in `ios/Sources/Transactions/TransactionListViewModel.swift` and `TransactionListView.swift` using `.scrollPosition(id:)`: capture the top-visible row id **before** the re-read and restore it after, so a person deep in a long list is not thrown to the top (FR-056, SC-010, research R14).
- [ ] T128 [US8] Subscribe to the signal from the list's `.task` in `ios/Sources/Transactions/TransactionListView.swift`, so the subscription is cancelled with the screen (I4).
- [ ] T129 [US8] Re-read `importedAccounts()` on the **same** signal in `ios/Sources/Import/ImportViewModel.swift`, so the front-door count and the list can never be refreshed from different moments (I5, FR-006, FR-057).
- [ ] T130 [US8] Confirm every engine read on this path happens off the main thread (`TransactionHistoryService` is an actor; no `Store` method is called from a view body or a `@MainActor` initialiser) and that memory does not grow without bound as pages accumulate — cap or window the retained pages if a scroll of the 10,000-row corpus says otherwise (FR-057, FR-061).
- [ ] T131 [US8] **GATE** `make lint && make ios-test` — T122–T124 green.

## Phase 11: Polish, gates and the record

- [ ] T132 [P] Confirm the S-suite runs under `make core-test` by default — not behind `--ignored`, not behind a feature flag — and record the measured values from `core/crates/kaname-core/tests/history_perf.rs` (first page, worst page, per-account spread, `account_summaries()` cost) in `specs/018-transaction-list/quickstart.md` § *The performance measurement*, replacing the planning-machine reference numbers with this build's.
- [ ] T133 [P] Audit that **no test in this slice is disabled**: `grep -rn "\.disabled(\|#\[ignore\]\|XCTSkip" ios/Tests ios/UITests core/crates/kaname-core/tests` must return nothing added by this slice — in particular the R17 determinism suite (T006, T007) and US1 AS-6's engine coverage are live and green.
- [ ] T134 [P] ⚠️ Record what US1 AS-6 now asserts, in `specs/018-transaction-list/quickstart.md` § *Definition of done*: after T008 and T008c, two **credit-card** accounts holding an identical date + description + amount each keep their own row — AS-6 holds as written. A **bank ledger and a card** still collapse such a row, which is 013's entire purpose and is fenced by T008b. Carry forward as an open finding for the slice that owns dedup: two accounts *of the same kind* are now never compared at all, which is a blunt guard — a person with two bank accounts, one of which itemises the other's card spends, would double-count. The narrow fix is a source-kind guard; a matcher that understands *why* two rows are the same purchase is a larger question.
- [ ] T135 [P] Audit every fixture added by this slice (`core/crates/kaname-core/tests/common/mod.rs`, every new `ios/Tests` file) and confirm it is synthetic: no real merchant, no real statement, no real account identifier, no plausible real card last-4 pattern (FR-064, SC-017).
- [ ] T136 [P] Update `.scratch/HANDOFF.md` §7 "Key reusable seams" with `history_page`, `account_summaries`, the `LIVE` constant, schema **v7**, `StoreProvider` and the widened networking audit — and carry **R17** (the matcher's cross-account collapse and the absent same-institution guard) and **R18** (`detectTransfers()` is still uncalled; wiring is the categorize slice's) forward as open items with their evidence.
- [ ] T137 [P] Update `AGENTS.md` with the two traps this slice adds: `ImportService.swift` is at the 400-line limit and the count block is the only headroom; and `make core-xcframework` before `make ios-gen`, never a bare `tuist generate`.
- [ ] T138 [P] Update the P3 status line in `docs/kaname-ios-plan.md` to record that the transaction list has landed, and that the DEBUG-only test-seeding hook slice — which is what would make SC-012 automatable for this screen and every P3 screen after it — is still scheduled before the categorize slice.
- [ ] T139 ⚠️ Run the **manual, release-blocking** gate in `specs/018-transaction-list/quickstart.md` § *The manual, release-blocking gate* on a real device with a release build: G1–G8 (accessibility: no truncated amount at the largest size, no occlusion by the bottom bar, VoiceOver as one coherent sentence per row, heading announcement with the year rule, filter announced and clearable, Reduce Transparency, Increase Contrast + Dark Mode, the date stays identifiable while scrolling) and G9–G14 (device performance: first screenful < 1 s on 10,000/8, no persistent blank rows, the 200-row comparison, filter apply/clear < 300 ms, an import while scrolled and filtered, a cancelled import changing nothing).
- [ ] T140 Fill the **Record here** table in `specs/018-transaction-list/quickstart.md` with the device, iOS build, app build commit, date run, the G1–G8 result and the G9/G11/G12 measurements. SC-012 is not satisfied by running the gate — it is satisfied by recording it.
- [ ] T141 **FULL GATE** `make core-lint` (repo-root `Makefile`).
- [ ] T142 **FULL GATE** `make core-test` — including the O/L/P/F/S suites, the v6→v7 migration test and the R17 determinism suite.
- [ ] T143 **FULL GATE** `make core-privacy-audit` — still green, still unchanged, still zero new dependencies.
- [ ] T144 **FULL GATE** `make lint` — `swiftlint --strict` and `swift-format lint --strict`; `ImportService.swift` ≤ 400 lines.
- [ ] T145 **FULL GATE** `make ios-gen` — depends on `core-xcframework`; never a bare `tuist generate`.
- [ ] T146 **FULL GATE** `make ios-test`.
- [ ] T147 **FULL GATE** `make import-audit` — the **widened** networking scan over all of `ios/Sources`, plus the glass, `#available(iOS 26` and bank-literal scans.

**Checkpoint**: The list keeps up with an import, the gates are green, the manual gate is recorded, and the two findings this slice did not own are carried forward with their evidence.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T002 blocks every engine test suite.
- **Foundational (Phase 2)**: depends on Setup. **BLOCKS every user story.** Internally:
  - **2A (R17 tie-break)** is independent of 2B/2C — different function, different file region. It can be developed in parallel but must land in PR A.
  - **2B (schema v7 + `LIVE`)** → **BLOCKS 2C**: `PAGE_SQL` is built from `LIVE`, and S1/S2 need the index to exist.
  - **2C (the two reads)** depends on 2B.
  - **2D (gate + `core-xcframework`)** depends on 2A, 2B and 2C — the FFI surface must be final before regeneration.
- **Design (Phase 2.5)**: depends on Setup only; **BLOCKS every UI task** in Phases 3–11.
- **US1 (Phase 3)**: depends on Phase 2 **and** Phase 2.5. Everything after depends on it.
- **US2 (Phase 4)**, **US4 (Phase 5)**: depend on US1's list existing.
- **US3 (Phase 6)** depends on US1; **US7 (Phase 7)** depends on US3 (empty state 6 needs the filter).
- **US5 (Phase 8)**, **US6 (Phase 9)**: depend on US1's row; independent of each other and of C.
- **US8 (Phase 10)**: depends on US1's paging **and** US3's filter — which is why it lands last.
- **Polish (Phase 11)**: depends on every story being complete. T139/T140 depend on everything.

### User Story Dependencies

- **US1 (P1)** — Foundational only. **The MVP.**
- **US2 (P2)** — US1. Adds no new surface; it pins the live rule end to end.
- **US4 (P4)** — US1. Ordering and grouping over the same rows.
- **US3 (P3)** — US1. Independent of US5, US6, US7's non-filtered states.
- **US7 (P7)** — US1 + US3 (two of its six states are filtered states).
- **US5 (P5)** — US1. Independently testable.
- **US6 (P6)** — US1. Independently testable; its transfer half needs a test-set flag, never app-side detection.
- **US8 (P8)** — US1 + US3.

### Within Each Story

- RED test tasks are written and **must be observed failing** before their implementation task.
- Engine before bridge; bridge before UI.
- `make core-xcframework` before any `tuist generate`, always through `make ios-gen`.
- A story is complete only when its verification-gate tasks pass.

### Parallel Opportunities

- **Setup**: T002, T003, T004 in parallel.
- **Foundational**: 2A (T005–T012, `load_dedup_candidates` + its tests) can run in parallel with 2B (T013–T019, `SCHEMA_V7`/`LIVE`) — both edit `store.rs`, so serialise the commits even when the work is parallel. Within 2C, the four RED suites T020, T021, T022 and T024 are four new files and fully parallel.
- **US1**: T048–T051 are four new test files — fully parallel. T055, T056, T057 are three new source files — fully parallel.
- **US3 / US7**: T084–T086 and T093–T095 are parallel within their own files.
- **US5 / US6**: Phases 8 and 9 touch different concerns of the same two files; staff them together only if the row view's edits are serialised.
- **Polish**: T132–T138 in parallel.

---

## Parallel Example: Phase 2C's RED suites

```bash
# Four new test files, no shared state — launch together:
Task: "RED core/crates/kaname-core/tests/history_order.rs (O1–O7)"
Task: "RED core/crates/kaname-core/tests/history_live.rs (L1–L5)"
Task: "RED core/crates/kaname-core/tests/history_paging.rs (P1–P5)"
Task: "RED core/crates/kaname-core/tests/history_perf.rs (S1–S2)"
```

## Parallel Example: User Story 1's new files

```bash
# Three new source files under a directory that does not exist yet:
Task: "Create ios/Sources/Transactions/TransactionListModels.swift"
Task: "Create ios/Sources/Transactions/TransactionListStrings.swift"
Task: "Create ios/Sources/Transactions/TransactionHistoryService.swift"
```

---

## Implementation Strategy

### MVP First (PR A + PR B)

1. Phase 1 — Setup (T001–T004)
2. Phase 2 — Foundational (T005–T044), **2B before 2C, always**; PR A merges here
3. Phase 2.5 — Design contract (T045–T047)
4. Phase 3 — User Story 1 (T048–T070)
5. **STOP and VALIDATE**: run the US1 independent test — two synthetic accounts, one combined list, every row correct and correctly attributed, zero network requests.
6. This is a shippable MVP: import stops being an act of faith.

### Incremental Delivery

PR A (engine) → PR B (US1 MVP, US2, US4) → PR C (US3, US7) → PR D (US5, US6) → PR E (US8 + polish). Each PR adds value without breaking the last, and each ends on the full verification gate.

---

## Recommended PR split

**147 tasks** across two languages, one migration, two new engine reads, six new FFI records, one shipped-defect fix, a new Swift directory of six files and eight user stories. The delivery order below is **mandatory, not advisory** (`plan.md` § *Delivery order*): PR A crosses the FFI, and Tuist resolves the xcframework path at generation time, so a PR mixing engine and interface work cannot be reviewed or bisected cleanly.

| PR | Tasks | Contents | Why it stands alone |
|---|---|---|---|
| **A — Engine** 🔒 | **T001–T044** | Setup + corpus builders; the **R17 dedup tie-break fix** with its cross-process determinism proof; schema v7's partial `DESC` index; the `LIVE` constant and its byte-identity assertion; `history_page`; `account_summaries`; the six `uniffi::Record`s; `ffi.rs` exports; the O/L/P/F/S suites; the v6→v7 migration test; `core-xcframework` | Rust-only plus one regeneration. Everything except the tie-break is purely additive, and the tie-break deserves a reviewer's full attention on its own. **Must merge first** — it crosses the FFI. |
| **B — The list** 🎯 | **T045–T083** | The design contract; `StoreProvider`; all six files of `ios/Sources/Transactions/`; the row **with its accessibility layout from the start**; incremental date grouping; the `NavigationStack` destination and `.safeAreaBar`; front-door rows become `NavigationLink`s and stop being `LabeledContent`; the front-door count switches to `account_summaries()`; the **widened networking audit**. US1, US2, US4 | 🎯 The first demoable PR and the natural place to stop and validate. The a11y layout ships with the row because retrofitting it is exactly how the parked occlusion finding happened. Depends on A. |
| **C — Filter and honesty** | **T084–T102** | The account filter (glass chrome on an opaque bar, always-visible scope, one-action clear, never persisted); the six empty states; the pluralisation helper; the "no blame words" and "no identifiers" string audits. US3, US7 | Entirely presentation and copy, reviewed with a simulator open. Depends on B; independent of D and E. |
| **D — What the engine already knows** | **T103–T121** | Per-row `Decimal` currency formatting and the no-aggregate audit; category names and the uncategorized label; the transfer **marking** (flag set by the test, detection deliberately unwired) and its mechanical guard; the VoiceOver / Dynamic Type / contrast suite and the empty-list system audit. US5, US6 | The correctness-of-detail PR. Ships R18's honest state: the marking is built and tested, `detectTransfers()` stays uncalled, and nothing claims otherwise. Depends on B; independent of C. |
| **E — Live and fast** | **T122–T147** | The `AsyncStream<Void>` import-completion signal; anchor capture and restore; the perf gates confirmed under `make core-test`; the manual gate **run and recorded**; the fixture audit; `AGENTS.md` and `.scratch/HANDOFF.md` carrying R17 and R18 forward; the full seven-target gate. US8 + Polish | Lands last because the anchor logic is only meaningful once C's filter and B's paging both exist, and because T139/T140's release-blocking manual gate should see the finished screen. Depends on B **and** C. |

**Ordering constraints across PRs**: A → B → {C, D in either order or in parallel} → E. E depends on C for the filter invariants (T123) and on B for paging. Every PR runs the full Local Verification Gate — `make core-lint && make core-test && make lint && make ios-test`, plus `make import-audit` — before it opens, and PR A additionally runs `make core-privacy-audit` and `make core-xcframework` before `make ios-gen`.

---

## Notes

- `[P]` = different files, no shared state, no dependency on an incomplete task.
- `[Story]` maps a task to its user story for traceability; Setup / Foundational / Design / Polish tasks carry none.
- **Verify every RED test actually fails before implementing it.** A test that passes on first write is a test that proves nothing — and T006/T007 in particular can pass *by luck* against the shipped defect, so re-run them.
- **No `.disabled(…)`, no `#[ignore]`, no `XCTSkip` in this slice.** T133 enforces it.
- **`rustfmt` reformats your edits**: after a Rust edit run `make core-fmt` and re-read the file before the next edit — your `old_str` may no longer match.
- **swift-format `[Spacing]` rejects trailing inline comments** — put comments on their own line.
- **`cargo` is not on the default PATH**: `export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"` in every shell.
- **`ImportService.swift` is at exactly 400 lines.** T067 is the only thing that creates headroom; T125 is the only thing allowed to spend it.
- **Seed the perf corpus by direct SQL** (151 ms) and the correctness corpus through the real import path (11.8 s at 10k) — and give every row a globally unique amount and description, or the corpus de-duplicates itself and the gate measures an eighth of what it claims.
- **Never** commit a real statement, a real merchant record or a real account identifier.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
