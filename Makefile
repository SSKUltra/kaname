.PHONY: bootstrap core-test core-lint core-fmt core-xcframework ios-gen ios-test lint

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

# --- Everything ---
lint: core-lint
	cd ios && swiftlint --strict && swift-format lint --recursive --strict Sources Tests
