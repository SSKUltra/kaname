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

### Reading a statement

Extraction is **geometry-first** and platform-side: a line is one *printed row*, rebuilt from
where the glyphs sit, never the PDF text layer's own newlines. It lives in
`ios/Sources/Import/PrintedRows.swift` (which words form a row) and `WordGeometry.swift` (where
a word is, and the three separate ways PDFKit gets that wrong). Evidence is
`fixtures/geometry/*.json` — synthetic layout signatures rendered to real PDFs at test time,
each of which must fail against the pre-017 extraction to count. No real statement, and no
fragment of one, ever enters this repository.


## Two traps this repo will spring on you (018)

**1. `ios/Sources/Import/ImportService.swift` sits on the SwiftLint file-length limit.** The
threshold is 400 lines and `make lint`'s `--strict` turns the warning into a failure, so *one*
added line fails the gate. It is at **393** as of 018 PR E, and the only reason there is any
room at all is that the front-door count moved into the engine. If you need to add to it,
**move something out** — do not reformat to squeeze under. New platform code for the
transaction list belongs in `ios/Sources/Transactions/`.

**2. Never run a bare `tuist generate`.** `tuist` resolves the xcframework path *at generation
time*, so after any change to `core/src/ffi.rs` or any `#[uniffi::export]` you must run
`make core-xcframework` **then** `make ios-gen` (which depends on it). Skipping the rebuild
yields "cannot find `HistoryPage` in scope" — a Swift error that is not a Swift problem, and
which sends you looking in the wrong language.
