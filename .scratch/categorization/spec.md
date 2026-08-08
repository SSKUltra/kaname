# Spec — Deterministic Categorization Stack (kaname-core)

Status: ready-for-agent

> Feature: the free, on-device deterministic categorizer. Design of record:
> `docs/adr/0005-categorization-deterministic-stack.md` (plus `0001` monetization,
> `0003` AI-is-Pro). Vocabulary: `CONTEXT.md` (Categorization section). Constitution
> `v2.0.0` governs (financial data on-device; AI is Pro).

## Problem Statement

When I import my bank and credit-card statements, every transaction lands
**uncategorized**. Hand-labelling hundreds of rows is tedious, and I want my spending
sorted into meaningful buckets (Groceries, Fuel, Rent/EMI, Salary…) so I can see where my
money actually goes — **instantly, on my device, with nothing sent to a server** for the
free experience.

## Solution

Kaname assigns each transaction a **Category** on-device using a deterministic,
first-wins **categorization stack**: it honours the statement's own category hint, reuses
what it already knows about a merchant (the "memory"), applies my rules, and recognises
India-specific credit-card patterns — falling back to leaving a transaction uncategorized
rather than guessing. Each Category rolls up to a **Classification** money-bucket
(`SPEND / INCOME / INVESTMENT / TRANSFER / CC_PAYMENT / REFUND`) that analytics consume.
The categorizer is a **pure engine function** — deterministic and reproducible against the
web engine byte-for-byte — so the same statement always sorts the same way.

## User Stories

1. As a Kaname user, I want each imported transaction assigned a Category automatically, so that I don't have to label everything by hand.
2. As a Kaname user, I want categorization to run entirely on my device, so that my financial data never leaves my phone for this feature.
3. As a Kaname user, I want categorization to be instant even across years of history, so that import never feels slow.
4. As a Kaname user, I want the statement's own category hint honoured first (the source-category map, T1), so that issuers that already label a row are respected.
5. As a Kaname user, I want a merchant I've categorized before to be categorized the same way again (the merchant map / "memory", T2), so that my past decisions stick.
6. As a Kaname user, I want my own rules applied (T3) — by keyword, regex, or amount range — so that I can steer categorization the way I want.
7. As a Kaname user, I want India-specific credit-card patterns recognised (CC rules) — e.g. a credit-card **bill payment** from my bank, or a card **inflow** — so that they're bucketed correctly and excluded from spend.
8. As a Kaname user, I want the stages applied in a fixed **first-wins** order (CC rules → T1 → T2 → T3), so that the outcome is predictable.
9. As a Kaname user, I want a transaction left **uncategorized** when no stage matches, so that Kaname never silently guesses wrong.
10. As a Kaname user, I want each Category to carry a Classification money-bucket, so that my dashboards can separate spend from income, transfers, investments, and refunds.
11. As a Kaname user, I want transfers and credit-card bill payments kept out of "spend", so that my spending totals aren't double-counted.
12. As a Kaname user, I want the 23 sensible Indian defaults available out of the box, so that I don't have to build a taxonomy myself.
13. As a Kaname user, I want my **own** categories (beyond the defaults) to work in rules and the merchant map, so that I'm not limited to the presets.
14. As a Kaname user, I want direction (debit/credit) taken from the statement's own Dr/Cr, never the amount's sign, so that polarity is always correct.
15. As a Kaname user, I want to see *why* a transaction got its Category (which stage fired), so that I can trust and, later, correct it.
16. As a Kaname user, I want categorization results to be identical every time for the same input, so that re-importing or re-running never reshuffles my data.
17. As a developer, I want a single pure entry point `categorize()` that takes the catalog, merchant-map, rules, and source-map as inputs and returns a decision, so that the engine stays deterministic and storage-agnostic.
18. As a developer, I want the categorizer to reference categories by a stable **CategoryRef** (built-in code or caller-supplied id), so that the pure core needs no database.
19. As a developer, I want the categorizer to reuse the already-ported `normalize_narration` and matcher, so that the merchant map keys exactly as dedup does and I don't re-port logic.
20. As a developer, I want the whole stack proven byte-for-byte against golden fixtures captured from the web engine, so that on-device output matches the proven engine.
21. As a developer, I want the categorizer reachable across the UniFFI bridge with one Swift bridge test, so that the app can call it natively.
22. As a developer, I want T3 rules resolved by priority (lower wins; user rules before system rules), so that rule conflicts are deterministic.
23. As a maintainer, I want the LLM stage (T4) explicitly excluded from this free deterministic slice, so that AI stays a Pro, server-side concern (ADR-0003).
24. As a maintainer, I want fixtures to be synthetic/redacted, so that no real statement data enters the repo (Constitution V).

## Implementation Decisions

- **New module + FFI surface in `kaname-core`.** A `categorize` module exposes one pure,
  first-wins entry point plus its result types, re-exported and surfaced over UniFFI.
- **Five-stage vocabulary, four ported.** The free port is the deterministic stages
  **CC rules → T1 source-category map → T2 merchant map → T3 rules** (first-wins). **T4
  (LLM) is Pro/out of scope** (ADR-0003). This corrects the plan's "T1=history, T2=rules"
  shorthand to the real stack (`CONTEXT.md`).
- **Pure over passed-in facts** (ADR-0005; plan §3.1 for the store): the engine reads facts and
  returns a decision; it never touches storage. Interface shape (the decision-carrying
  contract; validated by the perf prototype):
  - `categorize(txn, &catalog, &merchants, &rules, &source_map) -> Decision`
  - `CategoryRef = Builtin(code) | Custom(opaque id)` — a stable slug for one of the 23
    defaults, or the caller-supplied id already present in the passed-in facts.
  - `Decision { category_ref, stage_that_fired, matched_rule_id? }` — an audit trail;
    **no confidence field** (only the excluded LLM stage carried one).
- **Taxonomy into the core.** Port the **23 default categories** + the six-value
  `Classification` enum (`SPEND / INCOME / INVESTMENT / TRANSFER / CC_PAYMENT / REFUND`;
  none → fall back to `Direction`). The core carries **name + classification** only;
  colour / emoji / description remain platform-side display concerns.
- **CC rules are pure stage 0.** Port `cc_credit_rule` / `cc_debit_rule` verbatim for
  parity; exact token heuristics captured from the live web engine at implement-time.
- **Reuse, don't re-port.** `normalize_narration` (already in `dedup`), the matcher
  semantics (`KEYWORD` = case-insensitive substring, `REGEX`, `AMOUNT_RANGE`), and
  `parse_date` / `parse_amount` / `polarity::classify` already exist in the core.
- **Precedence:** first-wins across stages; within T3, lower `priority` wins (user rules
  before system rules). Direction is always from the statement's Dr/Cr, never the sign.
- **One slice** (ADR-0005): the full deterministic stack + orchestrator + `Decision`
  output ship together.

## Testing Decisions

- **Test the external behaviour at one seam** — the public `categorize()` function — not
  the internals of individual stages. Confirmed single-seam approach.
- **Rust golden fixtures** — new `fixtures/categorization/*.json` capturing **live
  web-engine ground truth** for T1 / T2 / T3 / CC rules (input transaction + catalog +
  merchant-map + rules + source-map → expected `Decision`), loaded via `load_fixture`
  with new `#[test]`s in `tests/parity.rs`. *Prior art: the dedup / coverage / transfer
  non-reader tests already in `parity.rs` (their own fixture + loader + `#[test]`).*
- **Rust unit tests** for **stage precedence / first-wins** and the uncategorized
  fall-through, in the new module.
- **One Swift bridge test** — `ios/Tests/CategorizationTests.swift`, proving `categorize`
  crosses UniFFI and returns a usable `Decision`. *Prior art: `CrossSourceDedupTests.swift`,
  `ReconcileTests.swift`.*
- **Reuse, don't re-test** `normalize_narration` + matcher (already covered by
  web-reference parity tests in `dedup.rs`).
- A good test asserts the returned `Decision` (category + stage that fired) for a given
  set of facts — never how a stage is implemented. Ground truth is captured by running
  the real Python helpers on the exact fixture inputs; **fixtures stay synthetic**.

## Out of Scope

- **Encrypted persistence** (SQLite / SQLCipher) — the store that supplies the facts and
  saves `transaction.category_id` (P2+, its own slice).
- **Learning / write-back** — turning a user's manual correction into a new merchant-map
  or source-category-map entry is a store/platform concern, not the pure engine.
- **The categorization UI** — reviewing, correcting, and bulk-recategorizing (P3).
- **Category CRUD / seeding UI** and display metadata (colour/emoji/localized names).
- **T4 / LLM (AI) categorization** — Pro, server-proxied (ADR-0003).
- **Tags and budgets** (separate features).

## Further Notes

- **Performance is settled.** The on-device perf spike
  (`core/crates/kaname-core/examples/prototype_categorization_perf.rs`) measured ~360 ms
  to categorize 100k transactions (realistic) and ~1.3 s worst case on-device — the pure
  scan needs no DB indexing for speed. (To be moved to a `prototype/` branch at
  `/to-tickets` and linked from the implementation ticket.)
- **Ground-truth capture** follows every prior slice: run the live web engine
  (`/Users/ssk/Projects/finance-tracker-phase/backend`, `.venv/bin/python`) on the exact
  fixture inputs and pin the byte-exact `Decision` outputs; the web tiers are
  `tier1_source_category`, `tier2_merchant_map`, `tier3_rules`, plus `cc_credit_rule` /
  `cc_debit_rule`.
- **Local Verification Gate** (constitution): `make core-lint && make core-test`, then the
  iOS gate, must pass before the PR.
