.PHONY: bootstrap core-test core-lint core-fmt core-privacy-audit core-xcframework ios-gen ios-test import-audit lint

# SQLCipher crypto backend is chosen per-OS with NO OpenSSL (Constitution I): Apple
# auto-selects CommonCrypto; on Linux we force LibTomCrypt by injecting the compile flag
# into the bundled SQLCipher (consumed in crates/kaname-core/build.rs). `export` makes it
# visible to every `cargo` invoked by a recipe. CI sets the same flag on its Linux job.
ifeq ($(shell uname -s),Linux)
export LIBSQLITE3_FLAGS := -DSQLCIPHER_CRYPTO_LIBTOMCRYPT
endif

# Install the toolchain (idempotent).
bootstrap:
	@rustup show >/dev/null 2>&1 || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	@command -v tuist >/dev/null 2>&1 || brew install tuist
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@command -v swift-format >/dev/null 2>&1 || brew install swift-format

# --- Rust core ---
core-test:
	cd core && cargo test --all --all-features

core-lint:
	cd core && cargo fmt --all -- --check && cargo clippy --all-targets --all-features -- -D warnings

core-fmt:
	cd core && cargo fmt --all

# Constitution Principle I gate: fail if any networking crate is in kaname-core's
# shipped (default-feature) dependency graph.
core-privacy-audit:
	./core/scripts/privacy-egress-audit.sh

# Build the UniFFI KanameCoreFFI.xcframework + generated Swift for the iOS app.
core-xcframework:
	./core/scripts/build-xcframework.sh

# --- iOS app ---
# `ios-gen` depends on `core-xcframework`: `tuist generate` resolves the xcframework
# path at generation time, so the framework MUST be built first (research D5).
ios-gen: core-xcframework
	cd ios && tuist generate --no-open

ios-test: ios-gen
	cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test

# The platform half of the Principle I gate: fail if any networking symbol appears on the
# statement-import path. `core-privacy-audit` cannot see Swift.
import-audit:
	./scripts/import-path-audit.sh

# --- Everything ---
lint: core-lint
	cd ios && swiftlint --strict && swift-format lint --recursive --strict Sources Tests
