# Contract: The absence proofs

**Feature**: `019-debug-test-seeding` | **Phase**: 1
**Interface kind**: two shell gates. They are the price this slice pays for putting a seeding
path in the app's own sources at all (FR-024–FR-032, SC-004, SC-005, SC-015).

There are **two** checks in **two** places, deliberately, because they answer different
questions at very different costs.

| | Scan A — source level | Scan B — artifact level |
|---|---|---|
| Question | "Is every seeding source file inside `#if DEBUG`?" | "Is any of it in the Release binary?" |
| Lives in | `scripts/import-path-audit.sh` (a **tenth** scan) | **NEW** `scripts/release-absence-audit.sh` |
| Invoked by | `make import-audit` (existing) | **NEW** `make release-audit` |
| Measured cost | **0.005 s** — a grep | **16.2 s** — it builds a Release binary (E1) |
| Requirement | FR-024, FR-027 | FR-025, FR-026, FR-028 |

Keeping them apart keeps the cheap gate cheap. `make import-audit` runs constantly; a
16-second build inside it would be the reason somebody stops running it.

---

## Scan A — the source-level check (tenth scan in `import-path-audit.sh`)

It follows the existing script's shape exactly, because that shape is the reason the other nine
are readable: **a rationale comment saying what the scan protects and why → the data → a
`grep … || true` → a FAIL block naming the requirement → an `OK` line.**

```bash
# DEBUG-boundary audit (019 FR-024) — every seeding source must be compiled out of Release.
# The boundary is the only thing standing between a path that fabricates a person's financial
# history and a build they install. `#if DEBUG` is checked here at the source, and
# `scripts/release-absence-audit.sh` checks the built artifact; this scan is the cheap half
# and runs on every `make import-audit`, which is why it is a grep and not a build.

SEED_DIR="$REPO_ROOT/ios/Sources/DebugSeed"

if [ -d "$SEED_DIR" ]; then
    unguarded=""
    while IFS= read -r f; do
        # Every file must open with `#if DEBUG` before its first non-comment, non-import line.
        head -20 "$f" | grep -qE '^#if DEBUG$' || unguarded="$unguarded$f"$'\n'
    done < <(find "$SEED_DIR" -name '*.swift')

    if [ -n "$unguarded" ]; then
        echo "import-audit: FAIL — seeding source outside a DEBUG guard:" >&2
        echo "$unguarded" >&2
        echo "Every file in ios/Sources/DebugSeed/ must be wrapped in #if DEBUG (019 FR-024)." >&2
        exit 1
    fi
fi

# The reverse direction: nothing outside DebugSeed/ may name the seeding surface unguarded.
seed_hits="$(grep -rInE '\b(KANAME_SEED_SCENARIO|SeedScenario|DebugSeed)\b' "$SOURCES_DIR" \
    --exclude-dir=DebugSeed | grep -v 'KanameApp.swift' || true)"
```

⚠️ **`grep -c` must not be used**, and a bare `grep` must not end a pipeline. Under `set -euo
pipefail`, `grep` exits **1** when it finds nothing — which is the **passing** case — and kills
the script. Every one of the nine existing scans ends `|| true` for this reason; the tenth does
too.

`KanameApp.swift` is excluded from the reverse scan by name because it is the one file outside
`DebugSeed/` that legitimately mentions it — three lines, inside `#if DEBUG`. That exclusion is
narrow on purpose: a second exclusion is a design smell and should move the code instead.

---

## Scan B — the artifact-level check (`scripts/release-absence-audit.sh`)

### Why source scanning is not enough

FR-025 asks for the absence to be **proved against the thing that ships**, not asserted about
its sources. A `#if DEBUG` that is present but ineffective — a file added to a target whose
Release configuration lacks the `DEBUG` compilation condition, a `Project.swift` edit that puts
`DebugSeed/` in the wrong `sources` glob — passes Scan A and fails reality. Only the binary
knows.

### 🚨 The trap this scan exists to avoid

Measured (research R4, evidence E4):

| Artifact | `nm -a` symbols | `FilterChromeLayout` in `strings`? |
|---|---|---|
| Release **build** product | **12,249** | ✅ yes |
| The same, after `strip -rSTx` | **157** | ⛔ no |

`-showBuildSettings` reports `STRIP_INSTALLED_PRODUCT = YES`, `STRIP_STYLE = all`,
`STRIP_SWIFT_SYMBOLS = YES` — but `DEPLOYMENT_POSTPROCESSING = NO`, so stripping runs on
`install` and `archive`, not on `build`. **A symbol scan over a stripped artifact is vacuously
green**: it finds nothing because there is nothing to find, and reports success.

Three consequences, all mandatory:

1. **The audit builds its own artifact**, pinning the `build` action and the configuration:
   `xcodebuild -configuration Release -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO`
   with its own `-derivedDataPath` outside the tree. It never scans an artifact somebody else
   produced, because it cannot know how.
2. **It self-checks before it concludes.** Before asserting an absence, it asserts two
   *presences* it knows must hold — a shipping symbol (`FilterChromeLayout`) and a shipping
   string literal (`Show all accounts`). If either is missing, the artifact is stripped,
   mis-built or in the wrong place, and the audit **fails as inconclusive** rather than passing.
   This is the whole difference between a proof and a formality.
3. **It scans both `nm` and `strings`.** They fail differently: `strip` removed the symbol but
   the **string literal survived**, and a code path can carry an identifying literal with no
   distinguishable symbol at all.

### The shape

```bash
#!/usr/bin/env bash
#
# Release absence audit (019 FR-025, FR-026, SC-004) — prove that no seeding path is present
# in the built Release binary. Source scanning is `import-path-audit.sh`'s tenth scan; this is
# the half that reaches the artifact, because a #if DEBUG that is present but ineffective
# passes a source scan and ships anyway.
#
# ⚠️ This script builds its OWN artifact and SELF-CHECKS. A stripped binary yields zero
# symbols, so a naive scan over one is vacuously green. Measured: 12,249 symbols before
# `strip -rSTx`, 157 after. The self-check is not belt-and-braces; it is the proof.

set -euo pipefail

DD="$(mktemp -d)"; trap 'rm -rf "$DD"' EXIT

xcodebuild -workspace ios/Kaname.xcworkspace -scheme Kaname \
    -configuration Release -sdk iphonesimulator \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build > "$DD/build.log" 2>&1 \
    || { echo "release-audit: FAIL — Release build failed" >&2; tail -40 "$DD/build.log" >&2; exit 1; }

BIN="$DD/Build/Products/Release-iphonesimulator/Kaname.app/Kaname"

# --- Self-check: the scan must be capable of finding something ------------------
nm -a "$BIN" | grep -q 'FilterChromeLayout' \
    || { echo "release-audit: FAIL (inconclusive) — the binary carries no Swift symbols." >&2
         echo "It is stripped or mis-built; an absence scan over it would be vacuous." >&2; exit 1; }
strings -a "$BIN" | grep -q 'Show all accounts' \
    || { echo "release-audit: FAIL (inconclusive) — no known shipping literal found." >&2; exit 1; }

# --- The absence itself ---------------------------------------------------------
DENYLIST=(DebugSeed SeedScenario SeedStatement SeedRow KANAME_SEED_SCENARIO applyIfRequested)
pattern="$(printf '%s|' "${DENYLIST[@]}")"; pattern="(${pattern%|})"

sym_hits="$(nm -a "$BIN" | grep -E "$pattern" || true)"
str_hits="$(strings -a "$BIN" | grep -E "$pattern" || true)"
```

Then the usual FAIL blocks naming FR-025 and SC-004, and on success:

```
release-audit: OK (Release binary carries no seeding path; 12,249 symbols scanned, 6 terms)
```

Printing the symbol count on the **passing** line matters: it is the number a reader checks when
they suspect the gate has gone quiet.

### The five deliberate breaks (FR-030, SC-005)

Each must be watched turning the gate **red**, and each must be reverted in the same commit.

| # | Break | Which scan must fail |
|---|---|---|
| 1 | Remove `#if DEBUG` from one `DebugSeed/*.swift` | **A** and **B** |
| 2 | Move a seeding function into `ios/Sources/Transactions/` outside a guard | **A** and **B** |
| 3 | Reference `SeedScenario` from `RootView.swift` outside a guard | **A** (and B, via the build) |
| 4 | Add `KANAME_SEED_SCENARIO` as a plain literal in a shipping file | **A** and **B** |
| 5 | Point the audit at a `strip -rSTx`ed copy of the binary | **B**, as **inconclusive** — the self-check |

Break 5 is the one that would be skipped and is the one that matters most: it is the only test
of whether the proof is a proof.

---

## Wiring

```make
release-audit: ## Prove no seeding path is in the Release binary (~16s: it builds one)
	@bash scripts/release-absence-audit.sh
```

**CI** (`.github/workflows/ci.yml`, `ios` job) gains **both**, because FR-029 requires the
absence check to run there and (research R19) ⚠️ CI currently runs `core-privacy-audit` but
**never `make import-audit`** — nine existing scans have been local-only:

```yaml
- run: make import-audit
- run: make release-audit
```

⚠️ Also from R19: CI runs `swift-format lint --recursive --strict Sources Tests` while `make
lint` covers `Sources Tests UITests`. Since this slice's centre of gravity is `UITests/`, that
gap should close in the same PR or the local gate will catch formatting CI never sees.

### Cost

| Gate | Added cost |
|---|---|
| `make import-audit` | **+0.005 s** (nine scans → ten) |
| `make release-audit` | **16.2 s** — 16.21 s of build (measured, cold derived data), 0.03 s of scanning |

FR-028's separate-invocation requirement is met by `make release-audit` existing as its own
target; SC-014's "adds no measurable time to the routine gate" is met by keeping Scan B out of
`make import-audit`.
