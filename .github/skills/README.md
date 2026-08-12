# Agent skills

Skills available to coding agents working in this repo. Each is a directory containing a
`SKILL.md` (YAML front matter + instructions) and optional supporting files.

## Provenance

Kaname is a **public, Apache-2.0** repository, so every vendored skill records where it came
from and under what licence.

### Vendored from [`mattpocock/skills`](https://github.com/mattpocock/skills) — MIT

25 skills, installed and version-pinned by `skills-lock.json` at the repo root (each entry
records the upstream `source`, `skillPath` and a `computedHash`, so drift from upstream is
detectable):

`ask-matt`, `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`,
`grill-me`, `grill-with-docs`, `grilling`, `handoff`, `implement`,
`improve-codebase-architecture`, `prototype`, `research`, `resolving-merge-conflicts`,
`setup-matt-pocock-skills`, `tdd`, `teach`, `to-questionnaire`, `to-spec`, `to-tickets`,
`triage`, `wait-what`, `wayfinder`, `wizard`, `writing-for-agents`.

Their licence and copyright notice is reproduced verbatim in [`LICENSE.mattpocock`](LICENSE.mattpocock),
as MIT requires. **To update them, re-run the installer** so `skills-lock.json` stays truthful —
don't hand-edit a vendored `SKILL.md` unless you also intend to fork it (see below).

### Vendored from [`Dimillian/Skills`](https://github.com/Dimillian/Skills) — MIT

- `swiftui-liquid-glass/` — `references/liquid-glass.md` is upstream verbatim; its `SKILL.md`
  is **deliberately forked** and rewritten for Kaname's iOS 26 baseline (upstream assumes
  availability gating and fallbacks, which this project does not use). Attribution is at the
  foot of that `SKILL.md`. Not covered by `skills-lock.json`.

### Written for Kaname

`apple-appstore-reviewer`, `github-project-tracking`, `make-interfaces-feel-better`.

## Local forks

`grill-me/` is vendored but **locally modified** — it is reduced to a thin pointer at
`grilling/` and marked `disable-model-invocation: true` so the two overlapping skills don't
both auto-trigger. Its `computedHash` in `skills-lock.json` therefore no longer matches
upstream; that is intentional, not drift.

## See also

The repo-wide conventions these skills operate under: [`AGENTS.md`](../../AGENTS.md),
[`.github/copilot-instructions.md`](../copilot-instructions.md), and the constitution at
[`.specify/memory/constitution.md`](../../.specify/memory/constitution.md), which wins over
any skill.
