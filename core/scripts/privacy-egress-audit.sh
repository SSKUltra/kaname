#!/usr/bin/env bash
#
# Privacy-egress audit (Constitution Principle I) — fail if any networking crate can
# link into the shipped `kaname-core`. Free/core features run 100% on-device with zero
# network I/O; the parse path is pure, so no HTTP/socket/async-runtime/TLS/DNS crate has
# any business in the dependency graph.
#
# `cargo tree -e normal` resolves DEFAULT features, so the `cli`-feature bindgen tooling
# (clap, uniffi-bindgen, …) is correctly excluded — this is the graph that links into the
# shipped static/dynamic library. cargo additionally lists the crate's own dev-deps
# (e.g. serde_json, the fixture harness); those are inspected too, which only makes the
# audit stricter (a networking crate must appear NOWHERE near the core).

set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CORE_DIR"

# Crate names in kaname-core's default-feature normal dependency graph.
graph="$(cargo tree -p kaname-core -e normal --prefix none | awk '{print $1}' | sort -u)"

# Well-known networking / async-IO / TLS / DNS crates. Exact-name match (no substrings)
# to keep the audit precise.
DENYLIST=(
    reqwest hyper hyper-util h2 h3 http-body
    tokio tokio-util async-std smol mio polling
    ureq curl curl-sys isahc surf attohttpc
    native-tls openssl openssl-sys rustls boring quinn quiche tonic
    socket2 trust-dns-resolver hickory-resolver dns-lookup if-addrs
)

found=()
for crate in "${DENYLIST[@]}"; do
    if grep -qx "$crate" <<<"$graph"; then
        found+=("$crate")
    fi
done

if [ "${#found[@]}" -gt 0 ]; then
    echo "privacy-egress: FAIL — networking crate(s) in kaname-core deps: ${found[*]}" >&2
    echo "Free/core paths must run 100% on-device with zero network I/O (Constitution I)." >&2
    exit 1
fi

echo "privacy-egress: OK (no networking crate in kaname-core deps)"
