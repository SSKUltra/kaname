# `fixtures/geometry/` — synthetic word-geometry vectors

Every file here is a **word-geometry fixture**: fabricated words with fabricated
positions, standing in for the text layer a real statement PDF would emit. They exist so
the column-major extraction fix can be proven **without a single real statement entering
this repository**.

Contract: [`specs/017-column-major-pdf/contracts/geometry-fixture.md`](../../specs/017-column-major-pdf/contracts/geometry-fixture.md).

## Privacy rules (non-negotiable)

| # | Rule | Requirement |
|---|---|---|
| P1 | Every merchant, amount, date, account number and card number is **fabricated**. | FR-036, SC-010 |
| P2 | Header and marker literals come from the reader's **own published claim markers**, never harvested from a contributor's or holder's document. | ADR-0004 amendment, FR-039 |
| P3 | Every added file is reviewed to confirm it carries no token lifted from a real statement — including in `_comment` fields and commit messages. | FR-039 |
| P4 | No real statement, and no fragment of one, enters the repository in any form. | FR-039 |
| P5 | Card numbers are written masked (`3561XXXXXXXX6686` style) and the last four are invented. | FR-036 |

P2 is the rule that is easiest to get wrong: a header literal is admissible here only
because a reader under `core/crates/kaname-core/src/statement/` already publishes it as a
claim marker in open source. If a literal is not already in the registry, it does not
belong in a fixture.
