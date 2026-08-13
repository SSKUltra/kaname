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
