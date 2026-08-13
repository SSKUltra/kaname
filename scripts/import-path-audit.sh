#!/usr/bin/env bash
#
# Import-path networking audit (Constitution Principle I) — fail if any networking symbol
# appears anywhere on the statement-import path. The core's crate graph is audited
# separately by `core/scripts/privacy-egress-audit.sh`; this is the platform half of the
# same guarantee, because a networking call added in Swift would never show up there.
#
# The whole path — pick, extract, detect, parse, persist, categorize, summarise — is
# `ios/Sources/Import/`. Nothing in it may reach the network, so the audit is a symbol
# search rather than a review convention: it fails the build, not a discussion.

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

hits="$(grep -rInE "$pattern" "$IMPORT_DIR" || true)"
import_hits="$(grep -rInE "$import_pattern" "$IMPORT_DIR" || true)"

if [ -n "$hits" ] || [ -n "$import_hits" ]; then
    echo "import-audit: FAIL — networking symbol(s) on the statement-import path:" >&2
    [ -n "$hits" ] && echo "$hits" >&2
    [ -n "$import_hits" ] && echo "$import_hits" >&2
    echo "The import path must run 100% on-device with zero network I/O (Constitution I)." >&2
    exit 1
fi

file_count="$(find "$IMPORT_DIR" -name '*.swift' | wc -l | tr -d ' ')"
echo "import-audit: OK (no networking symbol in $file_count file(s) under ios/Sources/Import)"

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
