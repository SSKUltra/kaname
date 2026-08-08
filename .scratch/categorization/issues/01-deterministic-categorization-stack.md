# 01 — Deterministic categorization stack

**What to build:** any caller can categorize a transaction **fully on-device** by calling
a single pure engine function, `categorize(txn, catalog, merchants, rules, source_map) →
Decision`. It runs the **first-wins** stack — **CC rules → T1 source-category map → T2
merchant map → T3 rules** — and returns which **Category** was assigned (as a `CategoryRef`)
and which stage fired, or *uncategorized* when nothing matches. Categories carry a
**Classification** money-bucket. Behaviour reproduces the web engine **byte-for-byte** and
is reachable from Swift over the UniFFI bridge. Design of record:
`.scratch/categorization/spec.md`, `docs/adr/0005-categorization-deterministic-stack.md`;
vocabulary in `CONTEXT.md`.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

Interface shape (encodes the grilled decisions; validated by the perf prototype):

- `categorize(txn, &catalog, &merchants, &rules, &source_map) -> Decision`
- `CategoryRef = Builtin(code) | Custom(opaque id)`
- `Classification = SPEND | INCOME | INVESTMENT | TRANSFER | CC_PAYMENT | REFUND` (none → fall back to `Direction`)
- `Decision { category_ref, stage_that_fired, matched_rule_id? }` — **no** confidence field

**Acceptance criteria**

- [ ] `categorize(...)` exists as a pure function (no I/O) and returns a `Decision`; it reads the passed-in facts only — never touches storage.
- [ ] First-wins order is exactly **CC rules → T1 source-category map → T2 merchant map → T3 rules**; when no stage matches, the result is *uncategorized*.
- [ ] The **23 default categories** and the six-value `Classification` enum are ported (name + classification only; no colour/emoji/description in the core).
- [ ] **T1** maps `(bank_code, source_category)` → Category (exact lookup).
- [ ] **T2** (the "memory") matches on the reused `normalize_narration` — literal substring or precompiled regex — first match by priority.
- [ ] **T3** rules match by `KEYWORD` (case-insensitive substring), `REGEX`, or `AMOUNT_RANGE`; resolved by `priority` (lower wins; user rules before system rules).
- [ ] **CC rules** (stage 0) port `cc_credit_rule` / `cc_debit_rule` verbatim; exact token logic captured from the live web engine.
- [ ] Direction comes from the statement's Dr/Cr via `polarity::classify`, never the amount's sign.
- [ ] `CategoryRef` returns a stable built-in **code** for the 23 defaults, or echoes the caller-supplied **id** for user categories.
- [ ] Reuses the already-ported `normalize_narration`, matcher semantics, and `parse_date`/`parse_amount`/`polarity` — no re-porting.
- [ ] **Golden fixtures** under `fixtures/categorization/` capture live web-engine ground truth (T1/T2/T3 + CC rules) and are asserted in `tests/parity.rs` (new loader + `#[test]`s), following the dedup/coverage/transfer pattern; fixtures are **synthetic**.
- [ ] Rust **unit tests** cover stage precedence / first-wins and the uncategorized fall-through.
- [ ] `categorize` is exported over UniFFI; one Swift bridge test (`ios/Tests/CategorizationTests.swift`) proves it crosses the bridge and returns a usable `Decision` (prior art: `CrossSourceDedupTests.swift`).
- [ ] The **Local Verification Gate** passes: `make core-lint && make core-test`, then `make lint && make ios-gen && make ios-test`; privacy-egress audit stays green.
- [ ] The perf prototype (`core/crates/kaname-core/examples/prototype_categorization_perf.rs`) is moved to a `prototype/categorization-perf` branch out of `main` and linked from this ticket; `main` no longer carries it.
- [ ] Shipped as the proven two-commit PR (engine+fixtures+parity, then Swift test), CI green, per the per-slice workflow.
