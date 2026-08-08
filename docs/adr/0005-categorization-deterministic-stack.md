# Categorization: deterministic stack ported to the pure core (T4/LLM is Pro)

## Context

Port the web engine's transaction categorization to `kaname-core` as a free, on-device,
deterministic feature. Recon corrected the plan's "T1 = history, T2 = rules" shorthand:
the real engine is a five-stage, first-wins stack. AI (the LLM stage) is now Pro per
ADR-0003, so it is out of this port.

## Decision

1. **Adopt the real five-stage vocabulary** (recorded in `CONTEXT.md`): `CC rules → T1
   source-category map → T2 user-merchant map ("memory") → T3 rules → T4 LLM`. The **free
   on-device port is the four deterministic stages** (CC/T1/T2/T3). **T4 (LLM) is Pro**,
   server-side, and not part of this slice.
2. **Pure over passed-in facts.** A single first-wins entry point,
   `categorize(txn, &catalog, &merchants, &rules, &source_map) → Decision`, with no I/O.
   The encrypted store (ADR: persistence, P2+) loads the facts and writes the result; the
   engine never touches storage. Perf-validated on-device (~360 ms / 100k txns realistic,
   ~1.3 s worst case — `examples/prototype_categorization_perf.rs`).
3. **Taxonomy into the core.** Port the 23 default categories + the six-value
   `Classification` enum (`SPEND / INCOME / INVESTMENT / TRANSFER / CC_PAYMENT / REFUND`;
   none → fall back to `Direction`). The core carries **name + classification** only;
   colour / emoji / description are platform-side display concerns.
4. **CC rules are pure stage 0.** The India-specific `cc_credit_rule` / `cc_debit_rule`
   narration heuristics (no state) run before the tiers; ported verbatim for parity, with
   exact token logic captured from the live engine at implement-time.
5. **Category identity across the FFI:** `Decision` names the chosen category with a
   `CategoryRef = builtin(code) | custom(opaque id)` — a stable slug for the 23 defaults,
   or the caller-supplied id already present in the passed-in facts for user categories.
   The store resolves either to its row. Keeps the core DB-free while supporting built-in
   and user categories.
6. **Reuse, don't re-port.** `normalize_narration` (already in `dedup.rs`, the exact key
   the memory tier uses), the matcher semantics (`KEYWORD` = case-insensitive substring,
   `REGEX`, `AMOUNT_RANGE`), and `parse_date` / `parse_amount` / `polarity::classify` are
   all already in the core.
7. **One slice.** The full deterministic stack (CC/T1/T2/T3 + first-wins orchestrator +
   the `Decision` audit output) ships as a single slice, golden-tested per stage.

## Consequences

- **`Decision` shape:** `{ category_ref, stage_that_fired, matched_rule_id? }` — an audit
  trail of *which* stage assigned the category. **No confidence field** for the free port:
  only the LLM stage carried a confidence in the web engine, and that stage is Pro/out.
- **Precedence:** first-wins in stage order; within T3, lower `priority` wins (user rules
  before system rules).
- **Persistence is deferred** (P2+): this slice ships the pure function; wiring it to the
  encrypted store comes with the persistence layer.
