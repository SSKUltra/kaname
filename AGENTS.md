# AGENTS.md

Agent instructions for the Kaname repo. Repo-wide conventions and
Copilot-specific guidance live in
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Start here (task pickup)

New session? Read [`.scratch/HANDOFF.md`](.scratch/HANDOFF.md) first — it's the
current-status + what's-next index (then the constitution, then the feature's
`.scratch/<slug>/` spec + tickets).

## Agent skills

### Issue tracker

Issues and specs live as local markdown under `.scratch/<feature-slug>/`.
See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue
file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
