---
name: github-project-tracking
description: 'Turn any PRD or spec document into a complete GitHub project tracking setup. Auto-discovers spec/PRD documents in the repo, extracts phases/epics as Milestones and User Stories as Issues, creates priority + domain Labels, and sets up a GitHub Projects V2 Kanban board — all linked together. Works with Markdown, HTML, or plain-text docs. Trigger on: "set up the project", "create issues from the PRD", "bootstrap GitHub tracking", "create milestones and issues", "set up the Kanban board", "turn the spec into GitHub issues", "set up GitHub tracking".'
---

# GitHub Project Tracking

Turn any product spec or PRD into a full GitHub project tracking setup in one shot.

## What it creates

| Artifact | Details |
|----------|---------|
| **Milestones** | One per Phase / Epic / Sprint found in the spec |
| **Priority labels** | `priority: must` · `priority: should` · `priority: could` · `priority: defer` |
| **Domain labels** | Auto-inferred from project tech stack, or pass `--labels` to specify |
| **GitHub Project (V2)** | Kanban board with 5 columns (configurable) |
| **Issues** | One per User Story — pre-filled with story text + DoD checkboxes |

## Usage

Invoke with no arguments to use auto-discovery, or pass options:

```
/github-project-tracking
/github-project-tracking --docs docs/prd.md
/github-project-tracking --docs "docs/prd.md,docs/phases.html" --name "My Roadmap"
/github-project-tracking --labels "frontend,backend,data,infra"
/github-project-tracking --columns "Backlog,Up Next,In Progress,Review,Done"
```

| Argument | Default | Description |
|----------|---------|-------------|
| `--docs` | Auto-discover | Comma-separated paths to spec/PRD files |
| `--name` | Repo name + " Roadmap" | GitHub Project board name |
| `--labels` | Auto-inferred | Comma-separated domain label names |
| `--columns` | See below | Comma-separated Kanban column names |
| `--milestones-only` | false | Only create milestones, skip issues |
| `--issues-only` | false | Skip board/labels, only create issues |
| `--dry-run` | false | Print what would be created without creating anything |

### Default Kanban columns

```
Backlog → Ready for Dev → In Progress → In Review / Testing → Done
```

## Pre-flight Checks (MUST run before any other step)

Run these checks first and STOP if any fail — do not proceed until the user resolves them.

### 1. Check `gh` config directory permissions

```bash
ls -la ~/.config
```

If `~/.config` is owned by `root`, prompt the user to fix it before continuing:

```
⚠️  ~/.config is owned by root. gh cannot save its config there.
Run this to fix it, then try again:

  sudo chown -R $(whoami) ~/.config
```

### 2. Check `gh` auth status and required scopes

```bash
gh auth status
```

The output must show **all four** of these scopes: `repo`, `read:user`, `project`, `read:org`.

If the `project` scope (or any other required scope) is missing, STOP and prompt the user:

```
⚠️  Your gh token is missing required scopes (need: repo, read:user, project, read:org).
Run this to re-authenticate with the correct scopes, then try again:

  gh auth login --hostname github.com --scopes "repo,read:user,project,read:org" --web
```

> **Why this matters:** The `project` scope is required to create and populate a GitHub Projects V2
> board. Without it, issues and milestones will be created successfully but the board step will fail,
> requiring a second auth cycle and a second run.

### 3. Auth errors during execution

If any `gh` command fails with an auth or permission error during execution:
- **STOP immediately**
- Show the user the exact command to fix the issue
- Do **NOT** attempt to work around it, retry silently, or continue past the failed step

---

## Document discovery

The skill looks for spec/PRD documents in this priority order:

1. Path(s) from `--docs` argument
2. `docs/` directory — `*.html`, `*.md`
3. `.specify/features/*/spec.md`
4. `spec/` or `specs/` directory — `*.md`
5. `README.md` (fallback)

If multiple documents are found and `--docs` was not specified, list them and ask the user which to use.

## Structure extraction

The skill reads the document(s) and extracts:

| What | How it's detected |
|------|-------------------|
| **Milestones** | Sections headed Phase N / Epic N / Sprint N / vN.N; H1/H2 with a date or goal |
| **User stories** | Rows matching `US-XX`, `Story N`, "As a user I can…", or table rows in a stories table |
| **Priority** | Badges/columns/labels: must/should/could/defer, high/medium/low, P0/P1/P2, critical/major/minor — all normalised to the four standard priority labels |
| **Domain** | Inferred from story content + tech stack files (`package.json`, `requirements.txt`, etc.); or from `--labels` |

## Issue body format

Every issue body follows this structure so Copilot Chat can read `#N` and write targeted code:

```markdown
## User Story
**As a user** I can [action from story]
**So that** [outcome from story]

## Acceptance Criteria / Definition of Done
- [ ] [DoD item 1]
- [ ] [DoD item 2]

## Phase / Epic
[Milestone name]

## Notes
> Reference this issue in Copilot Chat with `#N` for context-aware code generation.
> Commit with `Closes #N` to auto-close and update milestone progress.
```

## Label colours

| Label | Hex | |
|-------|-----|-|
| `priority: must` | `#d93f0b` | 🔴 |
| `priority: should` | `#e4a40a` | 🟡 |
| `priority: could` | `#0075ca` | 🔵 |
| `priority: defer` | `#cccccc` | ⚫ |
| Domain labels | Auto-chosen from a built-in palette | 🎨 |

## Idempotency

All creation steps are idempotent. Re-running the skill on an existing repo will skip anything that already exists (milestones, labels, issues with the same title) and only create what's missing.

## Post-setup: link board to repo

After creating the project board, prompt the user to link it to the repo so it appears under the repo's Projects tab:

```bash
gh project link <project-number> --owner <owner> --repo <repo>
```

## Copilot Chat integration

Once issues are live:
- Type `#12` in Copilot Chat — it reads the user story and writes targeted code
- Commit `Closes #12` — GitHub auto-closes the issue and updates milestone progress
- Move cards on the board: **Backlog → Ready for Dev → In Progress → In Review / Testing → Done**
