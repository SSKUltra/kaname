#!/usr/bin/env bash
#
# Networking audit (Constitution Principle I) — fail if any networking symbol appears
# anywhere in the app's Swift sources. The core's crate graph is audited separately by
# `core/scripts/privacy-egress-audit.sh`; this is the platform half of the same guarantee,
# because a networking call added in Swift would never show up there.
#
# The scan covers **all** of `ios/Sources/`, not just the import path. It was narrower once,
# and the narrowing was the bug: the glass and bank-literal scans below already covered
# every source file while the networking scan — the one enforcing the promise a person
# actually hands Kaname their statements for — covered one directory. A file added anywhere
# else, `ios/Sources/Transactions/` included, would have shipped with no networking audit at
# all. Nothing in the app may reach the network, so this is a symbol search rather than a
# review convention: it fails the build, not a discussion.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORT_DIR="$REPO_ROOT/ios/Sources/Import"
SOURCES_DIR="$REPO_ROOT/ios/Sources"
SEED_DIR="$SOURCES_DIR/DebugSeed"
REGISTRY="$REPO_ROOT/core/crates/kaname-core/src/statement/registry.rs"

if [ ! -d "$IMPORT_DIR" ]; then
    echo "import-audit: FAIL — $IMPORT_DIR does not exist" >&2
    exit 1
fi

# Networking symbols and the frameworks that vend them. Word-boundary matched so a
# legitimate identifier that merely contains one of these as a substring is not a hit.
DENYLIST=(
    URLSession URLRequest URLConnection URLProtocol
    NWConnection NWListener NWBrowser NWPath NWEndpoint
    CFNetwork CFSocket CFStream
    getaddrinfo
)

pattern="$(printf '%s|' "${DENYLIST[@]}")"
pattern="\\b(${pattern%|})\\b"

# `import Network` and friends, matched as whole import statements so the word "Network"
# in prose or in a type name is not a false positive.
import_pattern='^[[:space:]]*(@[A-Za-z]+[[:space:]]+)?import[[:space:]]+(Network|CFNetwork|NetworkExtension)[[:space:]]*$'

hits="$(grep -rInE "$pattern" "$SOURCES_DIR" || true)"
import_hits="$(grep -rInE "$import_pattern" "$SOURCES_DIR" || true)"

if [ -n "$hits" ] || [ -n "$import_hits" ]; then
    echo "import-audit: FAIL — networking symbol(s) in the app's sources:" >&2
    [ -n "$hits" ] && echo "$hits" >&2
    [ -n "$import_hits" ] && echo "$import_hits" >&2
    echo "The app must run 100% on-device with zero network I/O (Constitution I)." >&2
    exit 1
fi

file_count="$(find "$SOURCES_DIR" -name '*.swift' | wc -l | tr -d ' ')"
echo "import-audit: OK (no networking symbol in $file_count file(s) under ios/Sources)"

# ---------------------------------------------------------------------------
# Bank-literal audit (FR-012 / SC-010) — the app must not know which banks exist.
#
# Every issuer identity lives in the Rust registry and reaches the app only as an opaque
# `Issuer` whose `display_name` is rendered verbatim. If a bank's id, code or name appears
# in Swift, some screen has started branching on which bank it is, and adding an eleventh
# issuer would no longer cost zero app lines.
#
# The literals are read out of the registry rather than listed here, so an issuer added
# tomorrow is guarded without touching this script.

if [ ! -f "$REGISTRY" ]; then
    echo "import-audit: FAIL — cannot read the issuer registry at $REGISTRY" >&2
    exit 1
fi

# `id: "…"` and `display_name: "…"` from the registry rows, `BANK_CODE` from the readers
# the rows point at.
literals="$(
    sed -nE 's/^[[:space:]]*(id|display_name):[[:space:]]*"([^"]+)".*$/\2/p' "$REGISTRY"
    sed -nE 's/^pub const BANK_CODE: &str = "([^"]+)".*$/\1/p' \
        "$REPO_ROOT"/core/crates/kaname-core/src/statement/*.rs
)"
literals="$(printf '%s\n' "$literals" | sort -u)"

if [ -z "$literals" ]; then
    echo "import-audit: FAIL — no issuer literals parsed from the registry" >&2
    exit 1
fi

bank_hits=""
while IFS= read -r literal; do
    [ -z "$literal" ] && continue
    # Word-boundary matched and case-sensitive: a bank code like AU or YES must not fire on
    # an unrelated word that merely contains it.
    hit="$(grep -rInE "\\b$(printf '%s' "$literal" | sed 's/[][\.^$*+?(){}|]/\\&/g')\\b" \
        "$SOURCES_DIR" || true)"
    if [ -n "$hit" ]; then
        bank_hits="$bank_hits$literal:
$hit
"
    fi
done <<EOF
$literals
EOF

if [ -n "$bank_hits" ]; then
    echo "import-audit: FAIL — bank literal(s) under ios/Sources:" >&2
    printf '%s' "$bank_hits" >&2
    echo "The app must stay issuer-agnostic: render Issuer.display_name, never a bank name" >&2
    echo "(FR-012 / SC-010). Adding an eleventh issuer must cost zero app lines." >&2
    exit 1
fi

literal_count="$(printf '%s\n' "$literals" | wc -l | tr -d ' ')"
echo "import-audit: OK (none of $literal_count registry bank literal(s) under ios/Sources)"

# ---------------------------------------------------------------------------
# Liquid Glass audit (FR-047) — the app's deployment target is iOS 26 precisely so that
# Liquid Glass is unconditional. An availability gate, a material fallback, or a
# hand-rolled blur all mean someone has started maintaining a second visual language for
# an OS this app cannot run on.

GLASS_DENYLIST=(
    '#available\(iOS 26'
    '#unavailable\(iOS 26'
    '\.ultraThinMaterial'
    '\.thinMaterial'
    '\.regularMaterial'
    '\.thickMaterial'
    '\.ultraThickMaterial'
    'UIVisualEffectView'
    'UIBlurEffect'
    'NSVisualEffectView'
)

glass_pattern="$(printf '%s|' "${GLASS_DENYLIST[@]}")"
glass_pattern="(${glass_pattern%|})"

glass_hits="$(grep -rInE "$glass_pattern" "$SOURCES_DIR" || true)"

if [ -n "$glass_hits" ]; then
    echo "import-audit: FAIL — availability gate, material fallback or hand-rolled blur:" >&2
    echo "$glass_hits" >&2
    echo "The deployment target is iOS 26, so Liquid Glass is unconditional: use" >&2
    echo ".glassEffect / GlassEffectContainer / .buttonStyle(.glass) and never a fallback." >&2
    exit 1
fi

echo "import-audit: OK (no availability gate or material fallback under ios/Sources)"

# ---------------------------------------------------------------------------
# Palette audit — the prominent fill and the style that needs it travel together.
#
# The accent is two tokens, because one colour cannot both be a fill carrying white text and a
# foreground read against a dark background: those want opposite things from Dark Mode, and
# using one for both shipped a 2.35:1 failure that a person found on a device
# (.scratch/016-statement-import-vertical/issues/02-accent-unreadable-as-text-in-dark-mode.md).
#
# `.buttonStyle(.glassProminent)` inherits the app tint, which is now the *text* token — filling
# a button with it puts a white label on light teal. `prominentAction()` applies the style and
# the fill token as a pair, so the only way to get one is to get both.
PROMINENT="$(grep -rIn 'buttonStyle(\.glassProminent)' "$SOURCES_DIR" | grep -v '/Theme.swift:' || true)"

if [ -n "$PROMINENT" ]; then
    echo "import-audit: FAIL - a prominent button is styled without the fill it was measured for:" >&2
    echo "$PROMINENT" >&2
    echo "Use prominentAction(), which applies .glassProminent and .kanameAccentFill together." >&2
    echo "Bare .glassProminent inherits the app tint - the text token - and a white label on" >&2
    echo "that measures 2.26:1 (ios/Tests/ThemeContrastTests.swift)." >&2
    exit 1
fi

echo "import-audit: OK (every prominent action carries the fill it was measured for)"

# ---------------------------------------------------------------------------
# Population audit (FR-006, FR-008, FR-045) — one definition of "the transactions a person
# has", and it lives in the engine.
#
# `list_transactions` is a **raw** read: it returns deleted rows and the superseded losers of
# a de-duplication, deliberately, so a re-import's provenance survives. Counting or listing
# from it means re-deriving the population in Swift under a second copy of the live rule —
# which is exactly how the front door once came to show a person twice as many transactions
# as the list did (`3ba7890`). The app reads history through `historyPage` and counts through
# `accountSummaries`, both of which apply the engine's `LIVE` predicate, and nothing else.
#
# The screen's own sources are held to more than that: re-sorting or re-filtering the rows
# the engine returned would be a second opinion about order or membership, and a count and a
# list that disagree is the defect this whole slice exists to prevent.
#
# The order is written down in exactly two places — the engine's SQL and comparator, and
# `specs/018-transaction-list/data-model.md` §2 — so a `sorted`, `sort(` or `reversed`
# anywhere under `ios/Sources/Transactions/` is a third (T080, FR-045). The app renders the
# sequence it was given; it does not have an opinion about what order that should be.

# A *call*, not a mention: the doc comment that explains why this read is raw must stay.
RAW_READ_PATTERN='listTransactions\('
raw_hits="$(grep -rInE "$RAW_READ_PATTERN" "$SOURCES_DIR" || true)"

if [ -n "$raw_hits" ]; then
    echo "import-audit: FAIL — raw transaction read under ios/Sources:" >&2
    echo "$raw_hits" >&2
    echo "listTransactions returns deleted and superseded rows. Read the history through" >&2
    echo "historyPage and count through accountSummaries (FR-006, FR-008)." >&2
    exit 1
fi

TRANSACTIONS_DIR="$SOURCES_DIR/Transactions"
SECOND_OPINION=(
    'isLive' 'supersededBy' 'isDeleted'
    '\brows\.filter' '\bgroups\.filter'
    '\bsorted\b' '\bsort\(' '\breversed\b'
)

if [ -d "$TRANSACTIONS_DIR" ]; then
    second_pattern="$(printf '%s|' "${SECOND_OPINION[@]}")"
    second_pattern="(${second_pattern%|})"
    second_hits="$(grep -rInE "$second_pattern" "$TRANSACTIONS_DIR" || true)"

    if [ -n "$second_hits" ]; then
        echo "import-audit: FAIL — the transaction list re-derives its own population:" >&2
        echo "$second_hits" >&2
        echo "Which rows exist, and in what order, is the engine's answer alone — the list" >&2
        echo "renders it and never re-decides it (FR-008, FR-045). The ordering key lives in" >&2
        echo "the engine's SQL and in data-model.md §2, and nowhere else." >&2
        exit 1
    fi
fi

echo "import-audit: OK (the engine is the only definition of the live population)"

# ---------------------------------------------------------------------------
# Filter-persistence audit (FR-041) — the account filter is a question being asked, never a
# fact about a person's data, and it must not survive a launch.
#
# The failure it prevents is quiet and expensive: somebody filters to one card on Friday,
# opens Kaname on Monday, and sees a fraction of their own spending with nothing on screen to
# say it is a fraction. Any storage reached from the transaction list — a preference, an
# iCloud key-value store, a scene-restoration payload — would make that possible, so the
# symbols are banned outright rather than reviewed for.

if [ -d "$TRANSACTIONS_DIR" ]; then
    PERSISTENCE_DENYLIST=(
        'UserDefaults' '@AppStorage' '@SceneStorage'
        'NSUbiquitousKeyValueStore' 'NSUserActivity' 'FileManager'
    )
    persistence_pattern="$(printf '%s|' "${PERSISTENCE_DENYLIST[@]}")"
    persistence_pattern="(${persistence_pattern%|})"
    persistence_hits="$(grep -rInE "$persistence_pattern" "$TRANSACTIONS_DIR" || true)"

    if [ -n "$persistence_hits" ]; then
        echo "import-audit: FAIL — the transaction list can remember something:" >&2
        echo "$persistence_hits" >&2
        echo "The account filter must not survive a launch: a person who filtered on Friday" >&2
        echo "must not open a fraction of their spending on Monday (FR-041)." >&2
        exit 1
    fi
fi

echo "import-audit: OK (the transaction list persists nothing of its own)"

# ---------------------------------------------------------------------------
# Aggregate audit (FR-025, FR-026, SC-011) — two currencies must never quietly become one.
#
# A day can hold rows in more than one currency, so any per-day, per-group or per-screen figure
# is either meaningless or conditional — and a conditional one is a figure that will eventually
# be shown when its condition doesn't hold. The defence is structural: there is no sum anywhere
# in this directory to be wrong, and this scan is what keeps it that way.
#
# Matched as *code* rather than as words: `sum` and `total` appear in the comments explaining
# why they are absent, and a scan that fires on its own explanation teaches people to delete
# the explanation.

if [ -d "$TRANSACTIONS_DIR" ]; then
    AGGREGATE_DENYLIST=(
        '\.reduce\(' '\breduce\(into:'
        '(var|let|func)[[:space:]]+(sum|total|subtotal|average|balance|aggregate)\\b'
        '\.sum\(\)' '\.average\(\)'
    )
    aggregate_pattern="$(printf '%s|' "${AGGREGATE_DENYLIST[@]}")"
    aggregate_pattern="(${aggregate_pattern%|})"
    aggregate_hits="$(grep -rInE "$aggregate_pattern" "$TRANSACTIONS_DIR" || true)"

    if [ -n "$aggregate_hits" ]; then
        echo "import-audit: FAIL — the transaction list computes a figure of its own:" >&2
        echo "$aggregate_hits" >&2
        echo "A day can hold more than one currency, so no total, subtotal, balance or" >&2
        echo "average may exist on this screen — not hidden, not conditional, not at all" >&2
        echo "(FR-025, FR-026, SC-011)." >&2
        exit 1
    fi
fi

echo "import-audit: OK (no total, subtotal, balance or average under ios/Sources/Transactions)"

# ---------------------------------------------------------------------------
# Tint audit (FR-073) — the app's accent is structural, not per-screen.
#
# `KanameApp.swift` applies `.tint(.kanameAccent)` app-wide, so every control on the
# transaction list inherits it. A `.tint(...)` inside this directory is the only way the
# system default (or a second accent) could come back on this screen, and a screen that
# tints differently from the rest of the app reads as a different app.

if [ -d "$TRANSACTIONS_DIR" ]; then
    tint_hits="$(grep -rInE '\.tint\(' "$TRANSACTIONS_DIR" || true)"

    if [ -n "$tint_hits" ]; then
        echo "import-audit: FAIL — a tint under ios/Sources/Transactions:" >&2
        echo "$tint_hits" >&2
        echo "The accent is applied app-wide in KanameApp.swift; a per-screen tint is how" >&2
        echo "the system default comes back (FR-073)." >&2
        exit 1
    fi
fi

echo "import-audit: OK (the transaction list inherits the app's own accent)"

# ---------------------------------------------------------------------------
# Transfer-detection audit (FR-018) — the app does not detect transfers, and must not start
# claiming it does by accident.
#
# `detect_transfers` exists in the engine and is tested there, but no Swift source calls it:
# `is_transfer` is 0 on every row of a real install. The marking is honest only while that
# stays true, so the call is banned in the app until a slice wires it *deliberately* — at
# which point this scan is the thing that has to be removed, in the same commit, by someone
# who has read why it was here.
#
# The second half is the copy: a test, a task or a string that says "detected" would document
# a feature that does not exist, which is worse than the missing feature.

detect_hits="$(grep -rInE '\bdetectTransfers\b' "$SOURCES_DIR" || true)"

if [ -n "$detect_hits" ]; then
    echo "import-audit: FAIL — the app calls transfer detection:" >&2
    echo "$detect_hits" >&2
    echo "Kaname does not detect transfers (FR-018, research R18). If this slice wires it," >&2
    echo "remove this scan in the same commit and update every string that says otherwise." >&2
    exit 1
fi

# Negations are the whole point of most of these lines — "Kaname does not detect transfers"
# is the documentation this scan exists to protect, so a line carrying a negation is kept.
# A grep cannot parse English, and a scan that tried would eventually delete its own reason.
claim_hits="$(grep -rInE 'transfers? (are|is|were) (auto|detect)|detects? (a )?transfers?|transfer detection (is|runs)' \
    "$SOURCES_DIR" "$REPO_ROOT/ios/Tests" \
    | grep -viE '\b(not|never|nothing|no|none|unwired|without|cannot|claims)\b' || true)"

if [ -n "$claim_hits" ]; then
    echo "import-audit: FAIL — something claims Kaname detects transfers:" >&2
    echo "$claim_hits" >&2
    echo "The marking is a marking. No source, test name or string may imply detection" >&2
    echo "(FR-018)." >&2
    exit 1
fi

echo "import-audit: OK (transfer detection is unwired, and nothing says otherwise)"

# ---------------------------------------------------------------------------
# DEBUG-boundary audit (019 FR-024, FR-027) — every seeding source must be compiled out of
# Release.
#
# `ios/Sources/DebugSeed/` fabricates a person's financial history so an automated run can
# reach a screen that has data on it. The `#if DEBUG` guard is the only thing between that and
# a build somebody installs, so it is checked mechanically rather than reviewed for. This is
# the cheap half of the proof — a grep, run on every `make import-audit`. The other half,
# `scripts/release-absence-audit.sh`, builds a Release binary and looks for the seeding path in
# the artifact, because a guard that is present but ineffective (a file in the wrong target, a
# configuration missing the DEBUG condition) passes a source scan and ships anyway.
#
# Before this scan existed, an unguarded file under ios/Sources/DebugSeed/ passed all nine
# scans above with nothing said (019 T005). Nothing else in this repository notices.

if [ -d "$SEED_DIR" ]; then
    unguarded=""
    while IFS= read -r f; do
        # `#if DEBUG` must open the file, ahead of any code — the doc comment above it is fine,
        # 20 lines of preamble is not.
        head -20 "$f" | grep -qE '^#if DEBUG$' || unguarded="$unguarded$f"$'\n'
    done < <(find "$SEED_DIR" -name '*.swift')

    if [ -n "$unguarded" ]; then
        echo "import-audit: FAIL — seeding source outside a DEBUG guard:" >&2
        echo "$unguarded" >&2
        echo "Every file in ios/Sources/DebugSeed/ must be wrapped in #if DEBUG (019 FR-024)." >&2
        exit 1
    fi

    # The reverse direction: nothing outside DebugSeed/ may name the seeding surface. The
    # guard being in the right place is worth nothing if the seeding vocabulary has leaked into
    # a file that ships unguarded.
    #
    # `KanameApp.swift` is excluded by name because it is the one shipping file that
    # legitimately names it: three lines, inside `#if DEBUG`, calling the entry point. The
    # exclusion is narrow on purpose — a second one is a design smell, and the answer to
    # wanting it is to move the code into DebugSeed/, not to widen this line.
    seed_hits="$(grep -rInE '\b(KANAME_SEED_SCENARIO|SeedScenario|DebugSeed)\b' "$SOURCES_DIR" \
        --exclude-dir=DebugSeed | grep -v 'KanameApp.swift' || true)"

    if [ -n "$seed_hits" ]; then
        echo "import-audit: FAIL — the seeding surface is named outside ios/Sources/DebugSeed:" >&2
        echo "$seed_hits" >&2
        echo "Seeding lives in ios/Sources/DebugSeed/ behind #if DEBUG, and is named outside it" >&2
        echo "only by KanameApp.swift's three guarded lines (019 FR-024, FR-027)." >&2
        exit 1
    fi

    seed_file_count="$(find "$SEED_DIR" -name '*.swift' | wc -l | tr -d ' ')"
    echo "import-audit: OK ($seed_file_count seeding file(s) under ios/Sources/DebugSeed, all #if DEBUG)"
else
    echo "import-audit: OK (no ios/Sources/DebugSeed directory)"
fi
