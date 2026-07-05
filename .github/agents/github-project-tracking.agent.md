---
description: Turn any PRD or spec document into a complete GitHub project tracking setup — milestones, labels, Kanban board, and one issue per User Story.
tools: ['bash', 'github/github-mcp-server/issue_write', 'github/github-mcp-server/projects_write']
---

## User Input

```text
$ARGUMENTS
```

Parse `$ARGUMENTS` for these optional flags before doing anything else:

| Flag | Variable | Default |
|------|----------|---------|
| `--docs <paths>` | `DOCS` | (empty — auto-discover) |
| `--name <string>` | `PROJECT_NAME` | (derive from repo name) |
| `--labels <list>` | `CUSTOM_LABELS` | (empty — auto-infer) |
| `--columns <list>` | `CUSTOM_COLUMNS` | (empty — use defaults) |
| `--milestones-only` | flag | false |
| `--issues-only` | flag | false |
| `--dry-run` | flag | false |

---

## Pre-flight checks

> **STOP at the first failure below. Do not proceed to the next step until the user resolves it.
> Do NOT attempt to work around auth or permission errors — prompt the user with the exact fix command.**

### 0. Check `gh` config directory permissions

```bash
ls -la ~/.config
```

If `~/.config` is owned by `root`, stop and tell the user:

```
⚠️  ~/.config is owned by root — gh cannot save its config there.
Fix it with:

  sudo chown -R $(whoami) ~/.config

Then try again.
```

### 0b. Check `gh` auth status and required scopes

```bash
gh auth status
```

The output must show **all four** of these scopes: `repo`, `read:user`, `project`, `read:org`.

If the `project` scope (or any other required scope) is missing, stop and tell the user:

```
⚠️  Your gh token is missing required scopes (need: repo, read:user, project, read:org).
Re-authenticate with the correct scopes:

  gh auth login --hostname github.com --scopes "repo,read:user,project,read:org" --web

Then try again.
```

> **Why upfront?** The `project` scope is required for Step 5 (board creation). Checking here
> prevents a situation where all issues are created successfully but the board step then fails,
> forcing a second auth cycle and a second full run.

### 1. Confirm this is a GitHub repo

```bash
git -C "$(git rev-parse --show-toplevel)" config --get remote.origin.url
```

Extract `OWNER` and `REPO` from the remote URL (handle both HTTPS `https://github.com/OWNER/REPO.git` and SSH `git@github.com:OWNER/REPO.git` formats).

> [!CAUTION]
> STOP if the remote is not a GitHub URL. Never create issues in a repo that doesn't match the remote.

### 2. Set project name

If `--name` was provided, use it as `PROJECT_NAME`.
Otherwise derive it from the repo name: title-case `REPO`, replace hyphens/underscores with spaces, append " Roadmap".
Example: `finance-tracker` → `Finance Tracker Roadmap`.

---

## Step 1 — Discover and read spec/PRD documents

### If `--docs` was provided
Use the supplied path(s) directly. Verify each file exists; warn and skip any that don't.

### Otherwise auto-discover
Search the repo in this priority order and collect all candidates:

```bash
# Priority 1: docs/ directory
find "$(git rev-parse --show-toplevel)/docs" -maxdepth 2 \( -name "*.md" -o -name "*.html" \) 2>/dev/null

# Priority 2: .specify feature specs
find "$(git rev-parse --show-toplevel)/.specify/features" -name "spec.md" 2>/dev/null

# Priority 3: spec/ or specs/ directory
find "$(git rev-parse --show-toplevel)" -maxdepth 2 -type d \( -name "spec" -o -name "specs" \) \
  -exec find {} -name "*.md" \; 2>/dev/null

# Priority 4: README.md fallback
ls "$(git rev-parse --show-toplevel)/README.md" 2>/dev/null
```

**If exactly one document is found:** use it automatically.
**If multiple documents are found:** list them and ask the user which to use before continuing.
**If no documents are found:** tell the user no spec/PRD files were found and ask them to specify one with `--docs`.

### Read the selected document(s)
Read the full content of each selected file. For `.html` files, extract visible text (strip style/script tags and HTML tags, preserving structure).

---

## Step 2 — Extract structure from the document(s)

Analyse the document content and build two lists: **milestones** and **user stories**.
Do this extraction as part of your reasoning — you do not need to run a script for it.

### Extracting milestones

Look for any of these patterns and treat each match as one milestone:
- `Phase N`, `Phase N.N` headings (e.g., "Phase 0 — Skeleton", "Phase 1: Auth")
- `Epic N`, `Epic: <name>` headings
- `Sprint N`, `Sprint: <name>` headings
- `v1.0`, `v2.0` release headings
- Major H2/H3 sections that describe a distinct deliverable with a goal statement

For each milestone, extract:
- `title` — the milestone title as written (e.g., "Phase 0 — Skeleton")
- `description` — the goal/summary sentence immediately below the heading (1–2 sentences max)

### Extracting user stories

Look for any of these patterns and treat each match as one user story:
- Table rows with an ID column (`US-XX`, `Story N`, `F-XX`, `FEAT-XX`, `T-XX`) and description columns
- Lines/paragraphs starting with "As a user I can…" or "As a [persona]…"
- Bullet points or numbered items that clearly describe a user-facing feature
- Checkbox lists (`- [ ]`) that represent features or acceptance criteria at the story level

For each user story, extract:
- `id` — the story identifier if present (e.g., `US-11`); generate a sequential one if absent
- `title` — a concise action phrase (≤60 chars), derived from the story text
- `body` — the full story text ("As a user I can… so that…")
- `dod` — list of Definition of Done / acceptance criteria items for this story (may be inline or in a parent phase's DoD section — use the phase DoD as a default if per-story DoD is absent)
- `milestone` — the milestone title this story belongs to
- `priority` — normalise to one of: `must`, `should`, `could`, `defer`
  - Detect from badges, columns, or labels: `must`/`should`/`could`/`defer` → direct map
  - `high`/`P0`/`critical` → `must`; `medium`/`P1`/`major` → `should`; `low`/`P2`/`minor` → `could`; `won't`/`defer`/`out of scope` → `defer`
- `domains` — list of domain label names that apply (see domain inference below)

### Inferring domain labels

**If `--labels` was provided:** use those label names exactly as the full domain label set.

**Otherwise auto-infer** by:
1. Check for `package.json` → include `frontend` if `react`/`next`/`vue`/`angular` found, `backend` if `express`/`fastapi`/`django`/`rails` found
2. Check for `requirements.txt` or `pyproject.toml` → include `backend` if present
3. Check for infra files (`Dockerfile`, `.github/workflows/`, `terraform/`, `azure.yaml`) → include `infra`
4. Check for AI/ML keywords in the doc (`LLM`, `Gemini`, `OpenAI`, `GPT`, `ML`, `embeddings`, `categoris`) → include `ai-pipeline`
5. Scan story titles and domains mentioned in the doc for other natural groupings

Produce a deduplicated final list of domain label names. If nothing can be inferred, default to: `frontend`, `backend`, `infra`.

Then assign `domains` to each story by matching keywords in the story title/body:
- Contains "UI", "chart", "dashboard", "screen", "page", "view", "design" → `frontend`
- Contains "API", "route", "model", "parser", "database", "migration", "schema" → `backend`
- Contains "LLM", "Gemini", "GPT", "categoris", "AI", "ML", "chat", "insight" → `ai-pipeline`
- Contains "deploy", "auth", "JWT", "CI/CD", "Azure", "Docker", "infra" → `infra`
- Any domain-specific keyword from `--labels` list → that label

A story can have multiple domain labels.

### Dry-run exit

If `--dry-run` was set, print the full extracted structure (milestone list + story list with labels and priorities) and stop here. Do not create anything in GitHub.

---

## Step 3 — Create Milestones

> Skip this step if `--issues-only` was set.

For each extracted milestone, create it via the GitHub REST API:

```bash
gh api repos/{OWNER}/{REPO}/milestones \
  -X POST \
  -f title="{MILESTONE_TITLE}" \
  -f description="{MILESTONE_DESCRIPTION}" \
  --jq '{number, title}' 2>&1
```

- On **HTTP 422** (already exists): query existing milestones to get the `number` for that title — you will need it later.
- Store a mapping of `milestone_title → milestone_number` for use in Step 6.

```bash
# Get existing milestones if needed
gh api repos/{OWNER}/{REPO}/milestones --jq '.[] | {number, title}'
```

---

## Step 4 — Create Labels

> Skip this step if `--issues-only` was set.

### Priority labels (always created)

| Name | Color | Description |
|------|-------|-------------|
| `priority: must` | `d93f0b` | Must-have — blocks the phase from shipping |
| `priority: should` | `e4a40a` | High value; include if capacity allows |
| `priority: could` | `0075ca` | Nice to have; defer under pressure |
| `priority: defer` | `cccccc` | Explicitly out of scope for now |

### Domain labels (from inferred or `--labels` list)

Pick a colour from this palette, cycling through it:
`bfd4f2`, `d4c5f9`, `0e8a16`, `5319e7`, `1d76db`, `f9d0c4`, `c2e0c6`, `fef2c0`

```bash
gh api repos/{OWNER}/{REPO}/labels \
  -X POST \
  -f name="{LABEL_NAME}" \
  -f color="{COLOR}" \
  -f description="{DESCRIPTION}" \
  --jq '{name}' 2>&1
```

On **HTTP 422** (already exists): skip silently.

---

## Step 5 — Create the GitHub Projects V2 Kanban Board

> Skip this step if `--issues-only` or `--milestones-only` was set.

### 5a. Get the repo owner node ID

```bash
gh api graphql -f query='{
  repository(owner: "{OWNER}", name: "{REPO}") {
    owner { id login }
  }
}' --jq '.data.repository.owner'
```

Store `OWNER_NODE_ID`.

### 5b. Create the project

```bash
gh api graphql -f query='
mutation {
  createProjectV2(input: {
    ownerId: "{OWNER_NODE_ID}"
    title: "{PROJECT_NAME}"
  }) {
    projectV2 { id number title }
  }
}' --jq '.data.createProjectV2.projectV2'
```

Store `PROJECT_ID` (node ID like `PVT_...`).

> **If you get a scope error here:** the pre-flight check should have caught this. Tell the user to run:
> `gh auth login --hostname github.com --scopes "repo,read:user,project,read:org" --web`
> then restart from the beginning.

### 5c. Discover the default Status field options

```bash
gh api graphql -f query='{
  node(id: "{PROJECT_ID}") {
    ... on ProjectV2 {
      field(name: "Status") {
        ... on ProjectV2SingleSelectField {
          id
          options { id name }
        }
      }
    }
  }
}' --jq '.data.node.field'
```

Store `STATUS_FIELD_ID` and the IDs of the default options (`Todo`, `In Progress`, `Done`).

### 5d. Set the Kanban columns

Determine the column names:
- If `--columns` was provided: use that comma-separated list
- Otherwise use the default five: `Backlog`, `Ready for Dev`, `In Progress`, `In Review / Testing`, `Done`

Map the first, middle, and last defaults to the three existing options (rename them); add any additional columns as new options:

```bash
gh api graphql -f query='
mutation {
  updateProjectV2Field(input: {
    projectId: "{PROJECT_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    singleSelectField: {
      options: [
        { id: "{TODO_OPTION_ID}",        name: "{COLUMN_1}", color: GRAY,   description: "..." }
        { id: "{IN_PROGRESS_OPTION_ID}", name: "{COLUMN_3}", color: YELLOW, description: "..." }
        { id: "{DONE_OPTION_ID}",        name: "{COLUMN_N}", color: GREEN,  description: "..." }
        { name: "{COLUMN_2}", color: BLUE,   description: "..." }
        { name: "{COLUMN_4}", color: ORANGE, description: "..." }
      ]
    }
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id options { id name } }
    }
  }
}'
```

Store all column option IDs. Store `FIRST_COLUMN_OPTION_ID` (the initial status all new issues will be set to).

---

## Step 6 — Create GitHub Issues

> Skip this step if `--milestones-only` was set.

For each extracted user story, create one issue:

```bash
gh api repos/{OWNER}/{REPO}/issues \
  -X POST \
  -f title="{STORY_ID}: {STORY_TITLE}" \
  -f body="{ISSUE_BODY}" \
  -F milestone={MILESTONE_NUMBER} \
  -f labels[]="priority: {PRIORITY}" \
  -f labels[]="{DOMAIN_LABEL_1}" \
  --jq '{number, html_url, node_id}' 2>&1
```

Add multiple `-f labels[]=...` flags for each domain label that applies.

Store each issue's `number` and `node_id`.

### Issue body template

Populate this template from the extracted story data:

```markdown
## User Story
**As a user** I can {story_action}
**So that** {story_outcome}

## Acceptance Criteria / Definition of Done
- [ ] {dod_item_1}
- [ ] {dod_item_2}
- [ ] {dod_item_3}

## Phase / Epic
{milestone_title}

## Notes
> Reference this issue in Copilot Chat with `#{number}` for context-aware code generation.
> Commit with `Closes #{number}` to auto-close this issue and update milestone progress.
```

If the story text is not in "As a user / So that" format, adapt it:
- Use the story description as the action
- Leave the "So that" blank if no outcome is stated

If no explicit DoD items were found for the story, use the phase-level DoD items as a starting checklist.

### Duplicate detection

Before creating an issue, check if one with the same title already exists:

```bash
gh api repos/{OWNER}/{REPO}/issues \
  --jq ".[] | select(.title == \"{ISSUE_TITLE}\") | {number, html_url}" 2>/dev/null
```

If a match is found, skip creation and use the existing issue's `node_id` for Step 7.

---

## Step 7 — Add all issues to the Project board

> Skip this step if `--milestones-only` was set.

For every issue (newly created or pre-existing), add it to the project and set its Status to the first column:

```bash
# Add issue to project — returns ITEM_ID
gh api graphql -f query='
mutation {
  addProjectV2ItemById(input: {
    projectId: "{PROJECT_ID}"
    contentId: "{ISSUE_NODE_ID}"
  }) {
    item { id }
  }
}' --jq '.data.addProjectV2ItemById.item.id'

# Set Status to first column
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    value: { singleSelectOptionId: "{FIRST_COLUMN_OPTION_ID}" }
  }) {
    projectV2Item { id }
  }
}'
```

---

## Completion report

Print a summary after all steps complete:

```
✅ GitHub project tracking is ready!

  Project      : {PROJECT_NAME}  (#{PROJECT_NUMBER})
  Milestones   : {N}  ({list of titles})
  Labels       : {N}  ({priority set} + {domain set})
  Issues       : {N} created  /  {N} already existed  /  {N} failed
  Board        : {N} columns  ({column names joined with →})

Next steps:
  • Link board to repo (shows under Projects tab):
      gh project link {PROJECT_NUMBER} --owner {OWNER} --repo {REPO}
  • Reference issues in Copilot Chat: type #12 to get code scoped to that story
  • Close issues on commit:           git commit -m "Closes #12"
  • Update issue status on the board: {FIRST_COLUMN} → ... → {LAST_COLUMN}
```

If any issues failed to create, list them by story ID and error message so the user can retry.

---

## Error handling

| Error | Action |
|-------|--------|
| `~/.config` owned by root | Tell user to run `sudo chown -R $(whoami) ~/.config` and retry |
| Missing `project` scope | Tell user to run `gh auth login --hostname github.com --scopes "repo,read:user,project,read:org" --web` and restart |
| Any auth/permission error mid-run | STOP immediately; show exact fix command; do NOT continue past the failed step |
| Milestone 422 (exists) | Query existing milestones, use the returned `number` |
| Label 422 (exists) | Skip silently |
| Issue creation failure | Log story ID + error; continue; report all failures at end |
| No spec docs found | Tell user; suggest `--docs path/to/spec.md` |
| Multiple docs found, no `--docs` | List them; ask user to choose before continuing |
| Rate limit (HTTP 429) | Wait 60 seconds and retry; GitHub allows ~30 issues/min via REST |
