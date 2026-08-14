# Specification Quality Checklist: The Transaction List

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-14
**Updated**: 2026-08-14 — both clarifications answered and folded in (Q1 combined list; Q2 manual a11y gate)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain — **both resolved; answers recorded under Clarifications**
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

## Constitution Alignment

- [x] Zero network I/O asserted on this path, including the new cross-account read (FR-062, SC-015)
- [x] Money as exact decimal, never floating-point (FR-016, SC-002)
- [x] Cross-currency arithmetic forbidden outright rather than deferred (FR-023–FR-027, SC-011)
- [x] Accessibility treated as a release gate (FR-065–FR-077, SC-012, SC-013, SC-014)
- [x] Fixtures synthetic only (FR-064, SC-017)
- [x] Prior hard-won constraints encoded as requirements, not conventions
      (live-row rule FR-007–FR-011; occlusion at accessibility sizes FR-067)

## Clarification Fold-In (Session 2026-08-14)

**Q1 — combined list is primary, per-account is a filter.** Worked through rather than
papered over:

- [x] Cross-account read stated as a **capability the screen needs**, in WHAT terms, with its
      shape left to `/speckit.plan` (FR-043–FR-046)
- [x] Recorded as **new engine surface crossing the FFI**, affecting the PR split
      (Why-this-slice, Assumptions, Dependencies)
- [x] Cross-account ordering with a **defined, total, stable same-date tie-break**
      (FR-028–FR-032, SC-009); tie-break rule and its reasoning recorded under
      "Decisions taken without asking"
- [x] Multi-currency **answered, not deferred**: currency always shown, nothing converted,
      no figure ever derived across currencies, no aggregate on date headings
      (FR-023–FR-027, US5, SC-011)
- [x] Filter behaviour fully defined — naming, applying, clearing, changing, relaunch
      (FR-036–FR-042, US3, SC-004)
- [x] Performance criteria restated over the **whole corpus**, not one account
      (FR-057–FR-061, SC-006, SC-007, SC-008)
- [x] Every prior single-account FR/SC re-checked; requirements renumbered contiguously
      **FR-001–FR-077**, success criteria **SC-001–SC-017**

**Q2 — manual accessibility gate for this slice.**

- [x] SC-012 is explicitly **manual and release-blocking**, worded so it cannot be read as a
      CI-enforced gate, and requires the build and date of the run to be recorded
- [x] The **reason** is stated plainly: the auditor runs against a launched app and cannot
      reach any screen behind an import — a limitation recorded in `.scratch/HANDOFF.md`
      under 016's T115/T123, not an oversight here
- [x] The automatable half is **explicitly enumerated and required** (FR-074, SC-013), so the
      manual gate stays as small as it honestly can be
- [x] The **DEBUG-only test-seeding hook** is recorded in Out of Scope as a planned future
      slice **before categorize**, named as what would make SC-012 automated for this screen
      and every P3 screen after it — and **not designed here** (FR-077)

## Validation Notes

**Iteration 1 (pre-clarification) findings, all resolved:**

1. *Success criteria contained a frame-rate figure expressed as a device capability.*
   Rewritten as user-observable outcomes (SC-007, SC-008).
2. *"The list must not re-read the whole account to draw one screenful" described a
   mechanism.* Restated as an outcome (FR-059).
3. *Duplicate visibility was initially left unstated.* Now decided explicitly, with reasoning.

**Iteration 2 (post-clarification) findings, all resolved:**

4. *The "adds no engine work" claim in the opening was false under Q1's answer.* Corrected:
   the slice now states it adds one new engine capability, and only that one.
5. *US3's relaunch scenario said only "the state this spec defines".* Untestable as written;
   now states the outcome directly (unfiltered on every launch), matching FR-041.
6. *Filter apply/clear had no measurable outcome.* Folded into SC-004 (one action each,
   exact populations) and SC-008 (first screenful within 300 ms on the large corpus).
7. *Mixed-currency handling risked being read as "avoid summing".* Strengthened to a
   prohibition on such a figure existing at all (FR-025), with date-group headings carrying
   no monetary aggregate (FR-026) so grouping can never force one.

**No open items.** Ready for `/speckit.plan`.
