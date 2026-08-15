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
