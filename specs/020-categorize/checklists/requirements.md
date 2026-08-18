# Specification Quality Checklist: Categorize

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-18
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

### Validation iterations

**Iteration 1** — three items failed and were fixed in the spec:

1. *No implementation details* — an early draft named `set_category` as the method to add and
   named `v8` as the schema version. Both are `/speckit.plan`'s decisions. Rewritten as
   capability requirements (FR-044, FR-045, FR-046) with the version left as an assumption.
2. *Success criteria are technology-agnostic* — a draft criterion measured seeded-launch time in
   seconds. `019/04` established that a wall clock in a UI test measures the machine, not the
   app. All timing criteria were removed and the reason recorded under Assumptions.
3. *Requirements are testable* — "the person is told plainly" was unfalsifiable. Split into
   FR-028 (what must be stated), FR-029 (vocabulary that must not appear, with SC-013 counting
   it) and FR-030/SC-006 (what was said must equal what happened).

**Iteration 2** — all Content Quality, Feature Readiness and remaining Requirement Completeness
items pass.

### The one item that remains open, deliberately

**No [NEEDS CLARIFICATION] markers remain** — ❌ **not met, by design.** The spec carries three
questions (Q1–Q3) posed to the repository owner rather than answered by assumption. Each has more
than one defensible answer and each changes the *shape* of the work:

- **Q1** — whether a remembered correction rewrites transactions already in the store. Two of the
  four options approach the bulk-recategorize scope this slice explicitly excludes, so guessing
  here would silently widen the slice.
- **Q2** — how much of a description defines "the same merchant". Guessing wrong yields a memory
  that matches exactly one row forever while telling the person the app learned something
  (FR-027, SC-008), and there is no undo surface in this slice to rescue an over-broad guess.
- **Q3** — whether the uncategorized worklist is a narrowing on slice 018's list or a surface of
  its own. This determines whether 018's six empty states multiply or whether a second surface
  must be held to 018's mechanical bans without inheriting them.

Everything else the feature description left open was decided and recorded under
§ *Decisions taken without asking* rather than escalated — nine decisions, each with the
requirement IDs that carry it.

### Status

Items marked incomplete require spec updates before `/speckit.plan`. This spec is **not** ready
for `/speckit.plan` until Q1, Q2 and Q3 are answered and folded into the requirements.
