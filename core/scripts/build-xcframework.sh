#!/usr/bin/env bash
#
# Build KanameCoreFFI.xcframework + the generated Swift bindings for the iOS app.
#
# Pipeline (research D4 / quickstart §1):
#   1. compile libkaname_core.a for device + both simulator arches,
#   2. generate Swift bindings in UniFFI "library mode",
#   3. lipo the two simulator arches into one universal static lib,
#   4. xcodebuild -create-xcframework (device slice + universal-sim slice + C module),
#   5. drop the high-level Swift at ios/Generated/ for the Tuist KanameCore target.
#
# Outputs are git-ignored build artifacts, regenerated on demand:
#   ios/Frameworks/KanameCoreFFI.xcframework   (C/FFI module the bindings import)
#   ios/Generated/kaname_core.swift            (high-level Swift API)
#
# The core stays pure/on-device — this script only compiles and packages it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"          # .../core
REPO_ROOT="$(cd "$CORE_DIR/.." && pwd)"
IOS_DIR="$REPO_ROOT/ios"
GEN_DIR="$IOS_DIR/Generated"
FW_DIR="$IOS_DIR/Frameworks"
XCFRAMEWORK="$FW_DIR/KanameCoreFFI.xcframework"

LIB="libkaname_core.a"
DEVICE_TARGET="aarch64-apple-ios"
SIM_TARGETS=("aarch64-apple-ios-sim" "x86_64-apple-ios")

cd "$CORE_DIR"

echo "==> [1/5] Building kaname-core static libs (release) for iOS targets"
for target in "$DEVICE_TARGET" "${SIM_TARGETS[@]}"; do
    echo "    - $target"
    cargo build --release --quiet --target "$target"
done

BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT

echo "==> [2/5] Generating Swift bindings (UniFFI library mode)"
cargo run --quiet --features cli --bin uniffi-bindgen -- generate \
    --library "target/$DEVICE_TARGET/release/$LIB" \
    --language swift \
    --out-dir "$BUILD_TMP"

echo "==> [3/5] lipo-ing the simulator arches into one universal static lib"
SIM_DIR="$BUILD_TMP/sim-universal"
mkdir -p "$SIM_DIR"
lipo -create \
    "target/aarch64-apple-ios-sim/release/$LIB" \
    "target/x86_64-apple-ios/release/$LIB" \
    -output "$SIM_DIR/$LIB"

echo "==> [4/5] Assembling the C module + creating the xcframework"
# The xcframework carries only the low-level C/FFI module (header + module.modulemap);
# create-xcframework requires the modulemap to be named "module.modulemap".
HEADERS="$BUILD_TMP/headers"
mkdir -p "$HEADERS"
cp "$BUILD_TMP"/*FFI.h "$HEADERS/"
cp "$BUILD_TMP"/*FFI.modulemap "$HEADERS/module.modulemap"

rm -rf "$XCFRAMEWORK"
mkdir -p "$FW_DIR"
xcodebuild -create-xcframework \
    -library "target/$DEVICE_TARGET/release/$LIB" -headers "$HEADERS" \
    -library "$SIM_DIR/$LIB" -headers "$HEADERS" \
    -output "$XCFRAMEWORK" >/dev/null

echo "==> [5/5] Placing generated Swift at ios/Generated/"
mkdir -p "$GEN_DIR"
rm -f "$GEN_DIR"/*.swift
cp "$BUILD_TMP"/*.swift "$GEN_DIR/"

echo "==> Done:"
echo "    $XCFRAMEWORK"
echo "    $GEN_DIR/$(cd "$GEN_DIR" && ls ./*.swift | xargs -n1 basename | tr '\n' ' ')"
