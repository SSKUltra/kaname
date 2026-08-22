#!/usr/bin/env bash
#
# Which UI test suites run in which CI shard — and the proof that every suite runs in exactly one.
#
# The iOS UI bundle is 75% of this repository's CI wall time (57 tests, ~1,790 s on a
# `macos-26-arm64` runner, measured on run 32388813072). Splitting it across parallel jobs is the
# only lever that shortens it without weakening a gate, because the runner is 3 cores and the
# tests are launch-bound rather than CPU-bound.
#
# 🚨 **A hand-written shard list has exactly one failure mode, and it is this repository's
# least favourite: a suite that belongs to no shard is never run, and a suite that never ran
# reports success.** That is the same defect as 019's `make ios-gen` trap one layer out. So the
# list below is a *single source of truth* read by both the workflow and `--verify`, and
# `--verify` runs on every pull request in the fast job — it fails in ~9 minutes if a suite is
# added, renamed or deleted without this file being updated.
#
# Usage:
#   ui-test-shards.sh --verify   # every suite is in exactly one shard, and every named suite exists
#   ui-test-shards.sh --count    # how many shards there are
#   ui-test-shards.sh 1          # the -only-testing: arguments for shard 1
#
set -euo pipefail

cd "$(dirname "$0")/../.."

# Balanced by *measured* suite duration, not by test count — the two are unrelated here, since
# `SeededHistoryShapeUITests` is one test that costs 155 s and `ImportFrontDoorUITests` is six
# that cost 66 s. Seconds are from run 32388813072 and are comments, never inputs: rebalance by
# re-reading a run's own timings, and expect them to drift as suites grow.
SHARD_1="SeededAccessibilityUITests"                                    # ~441 s
SHARD_2="SeededDeterminismUITests SeedContractUITests CategorizeMemoryUITests"  # ~470 s
SHARD_3="SeededEmptyStateUITests SeededHistoryShapeUITests CategorizeWorklistUITests"  # ~484 s
SHARD_4="CategorizeDetailUITests SeededWorklistAccessibilityUITests CategorizeSecondActionUITests SeededTransactionListUITests ImportFrontDoorUITests"  # ~445 s

SHARD_COUNT=4

shard() {
    case "$1" in
        1) echo "$SHARD_1" ;;
        2) echo "$SHARD_2" ;;
        3) echo "$SHARD_3" ;;
        4) echo "$SHARD_4" ;;
        *) echo "ui-test-shards: no shard '$1' (there are $SHARD_COUNT)" >&2; exit 1 ;;
    esac
}

all_declared() {
    for i in $(seq 1 "$SHARD_COUNT"); do shard "$i"; done | tr ' ' '\n' | grep -v '^$' | sort
}
# Every `XCTestCase` subclass in the bundle — the population the shards must cover exactly.
all_on_disk() {
    grep -hoE '^(final )?class [A-Za-z0-9_]+: XCTestCase' ios/UITests/*.swift \
        | sed -E 's/^(final )?class ([A-Za-z0-9_]+).*/\2/' \
        | sort -u
}

case "${1:-}" in
    --verify)
        # Compared de-duplicated, so a suite listed twice is reported *only* as a duplicate.
        # Comparing the raw list would also report it as a phantom, which sends the reader
        # looking for a rename that never happened.
        declared="$(all_declared | uniq)"
        on_disk="$(all_on_disk)"

        status=0

        missing="$(comm -13 <(echo "$declared") <(echo "$on_disk"))"
        if [ -n "$missing" ]; then
            echo "ui-test-shards: FAIL — these UI test suites are in NO shard, so CI never runs them:" >&2
            echo "$missing" | sed 's/^/  /' >&2
            echo "  Add each to a shard in $0 (balance by the timings in the comments)." >&2
            status=1
        fi

        phantom="$(comm -23 <(echo "$declared") <(echo "$on_disk"))"
        if [ -n "$phantom" ]; then
            echo "ui-test-shards: FAIL — these shard entries match no suite on disk (renamed? deleted?):" >&2
            echo "$phantom" | sed 's/^/  /' >&2
            status=1
        fi

        dupes="$(all_declared | uniq -d)"
        if [ -n "$dupes" ]; then
            echo "ui-test-shards: FAIL — these suites are in more than one shard, so they run twice:" >&2
            echo "$dupes" | sed 's/^/  /' >&2
            status=1
        fi

        [ "$status" -eq 0 ] || exit "$status"

        echo "ui-test-shards: OK ($(echo "$on_disk" | wc -l | tr -d ' ') UI suites, each in exactly one of $SHARD_COUNT shards)"
        ;;
    --count)
        echo "$SHARD_COUNT"
        ;;
    ''|--help|-h)
        sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        for suite in $(shard "$1"); do
            printf -- '-only-testing:KanameUITests/%s ' "$suite"
        done
        echo
        ;;
esac
