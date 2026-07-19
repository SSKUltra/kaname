# Specification Quality Checklist: Recognise the Same Purchase Across Two Sources On-Device — Cross-Source Transaction De-Duplication (the Pure In-Memory CANONICAL + FUZZY Matcher, Ported From the Web Engine Deduplicator, With No Database and No New Dependency)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-19
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
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

- **Validation result**: All items pass; the specification is ready for `/speckit.clarify` or `/speckit.plan`. Zero `[NEEDS CLARIFICATION]` markers were needed. The behaviour is **fully pinned** by the proven web engine (Constitution Principle V): `normalise_narration` (`normaliser.py`), the **L3 CANONICAL** and **L4 FUZZY** layers of `deduplicator.py`, and the `rapidfuzz` Jaro-Winkler similarity — with ground truth already captured (representative `normalise_narration` outputs and the exact `rapidfuzz` values 0.95 / 0.92 / 0.9125 / 0.9232). Open details were resolved as documented Assumptions (informed defaults consistent with the web engine and the already-shipped balance-chain and reconciliation checks) rather than questions.
- **Judgment call — the scope decision was pre-made by the user, so no clarification was raised**: The user explicitly fixed the scope to the pure in-memory subset (L3 CANONICAL + L4 FUZZY only) and enumerated the excluded layers (database/persistence, L1 SOURCE_REF, L2 EXACT-hash, L5 MERCHANT + merchant resolution, amount-drift SUPERSEDE, row mutation/deletion/persistence, and UI). The spec encodes that exact scope (FR-012, SC-016) and restates it under Out of Scope, so there was no open scope decision to surface.
- **Judgment call — the two matching constants are pinned data, not prescriptive technology**: The 60-character normalised-narration prefix (canonical), the ±1-day date window (fuzzy), and the inclusive 0.92 Jaro-Winkler threshold (fuzzy) are stated as testable behaviours (FR-006–FR-010, SC-001–SC-003, Edge Cases). These are the byte-for-byte behavioural constants from `deduplicator.py`, not engine technology choices.
- **Judgment call — the four Jaro-Winkler reference values are behavioural parity data**: The spec quotes concrete captured similarities — "swiggy bangalore"/"swiggy bangaluru" = 0.95 (match), "amazon"/"amazon pay" = 0.92 (match at the inclusive boundary), "fine dining"/"fine dine" = 0.9232 (match), "acme corp"/"acme corporation" = 0.9125 (no match). These are the constitution's golden-fixture parity vectors (Principle V) — behavioural acceptance data drawn from the pinned web `rapidfuzz` output — not implementation details, and all narrations are synthetic. This mirrors how slice 012 embedded concrete rupee amounts as parity data.
- **Judgment call — multiplicity and the deterministic ladder are user-facing behaviours**: "each existing transaction is consumed by at most one incoming" (US3, FR-003, SC-005), "canonical before fuzzy" (US6, FR-004, SC-006), and "first unconsumed existing wins" (US6, FR-004, SC-007) are stated as verifiable outcomes with concrete N-vs-M examples. They describe *what* the matcher decides (only true duplicates are matched; genuine repeats survive), not *how* it is coded — the danger they guard against (silently deleting a real, distinct purchase) is a user-facing data-safety concern.
- **Judgment call — read-only / identification-only is a first-class guarantee**: US5, FR-002, and SC-009/SC-010 require that the matcher never mutates, drops, reorders, merges, or persists a row and that it only **identifies** duplicates (naming the incoming, the existing it duplicates, and the layer). This is stated as a verifiable, user-facing outcome (no data loss; an explainable match), consistent with the web behaviour and with the shipped checks being read-only trust signals. Acting on the matches (drop/merge/persist) is explicitly deferred (Out of Scope).
- **Judgment call — "no new runtime dependency" via a hand-rolled Jaro-Winkler**: FR-010, FR-023, and SC-016 require the on-device Jaro-Winkler to reproduce `rapidfuzz` byte-for-byte while adding no new dependency. This is a scope/architecture outcome mandated by the constitution (dependencies reviewed; prefer stdlib) and stated by the user as a hard constraint; `rapidfuzz` is named only as the web-side source of truth, never as an on-device choice.
- **Judgment call — the headline "one purchase, not two" framing is business-facing**: US1's value (a purchase appearing in both a bank statement and a card statement is recognised as one purchase, not two — no double-counting), US3's multiplicity (genuinely separate identical purchases both survive), and US4's protection (a same-amount purchase at a clearly different merchant is not collapsed) are written in plain, non-technical terms as the user requested; the normalisation and Jaro-Winkler examples serve as their acceptance criteria.
- **Judgment call — technology proper nouns are confined to non-prescriptive locations**: The only technology names in the document are intentional and confined to the verbatim **Input** line, the **Assumptions / Dependencies / Out of Scope** sections (where locked decisions such as UniFFI, exact-decimal money, and deferred scope like SQLite/SQLCipher are recorded, each noted as belonging to `/speckit.plan`), the constitution-mandated gate names (privacy-egress test, iOS Local Verification Gate, CI), and the web-engine source-of-truth names used as the parity reference (`normalise_narration`, `normaliser.py`, `deduplicator.py`, `rapidfuzz`, and the web parity tests). No engine module/type/regex is prescribed in the requirements themselves.
- **Judgment call — the Rust↔Swift bridge reachability outcome (US8 / FR-015 / SC-014)**: The bridge (the Rust core reached from the native app via UniFFI) is **locked architecture** from Constitution Principle II and the shipped P1 bridge slice, not a choice made here. The user framed on-device delivery of an engine capability, and every prior slice landed bridge reachability as a verifiable outcome; US8/FR-015/SC-014 state it as the measurable outcome that the app can call the matcher and receive the identified matches with their layers, mirroring the shipped balance-chain and reconciliation exposure.
- **Judgment call — accessibility & privacy vocabulary**: References to Human Interface Guidelines, Dynamic Type, Dark Mode, VoiceOver, "zero network I/O", and "no telemetry" are treated as user-facing outcomes mandated by the constitution's Privacy and Native Experience principles, not as framework/API implementation choices.
- Items marked incomplete would require spec updates before `/speckit.clarify` or `/speckit.plan`; none are incomplete.
