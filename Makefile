.PHONY: bootstrap core-test core-lint core-fmt core-privacy-audit core-xcframework ios-gen ios-test import-audit lint reference-check reference-shapes

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
	@# The simulator keeps the app's container between runs, so a statement imported by an
	@# earlier run leaves an account behind — and the front door then shows the accounts
	@# list instead of the empty state. The accessibility audit dutifully passes or fails
	@# against the wrong screen. Boot and wipe first so the gate audits what it says it does.
	@xcrun simctl bootstatus "iPhone 16" -b >/dev/null 2>&1 || true
	@xcrun simctl uninstall "iPhone 16" in.beaconbrain.kaname >/dev/null 2>&1 || true
	cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test

# The gate no fixture can close: run the real extractor over the operator's OWN statements
# and print counts. The directory never leaves their machine and nothing is written anywhere
# — see ios/Tests/ReferenceSetVerification.swift. Usage:
#     make reference-check DIR=/path/to/your/own/statements
#
# ⚠️ `TEST_RUNNER_` is load-bearing. `xcodebuild` does NOT pass the shell environment to a
# process running in the simulator; it forwards only variables with that prefix, stripping it.
# Setting KANAME_REFERENCE_DIR directly leaves the suite skipped — and a skipped suite reports
# "TEST SUCCEEDED" with no counts at all, which is the one outcome that looks like a pass.
reference-check: ios-gen
	@test -n "$(DIR)" || { echo "usage: make reference-check DIR=/path/to/statements"; exit 2; }
	@test -d "$(abspath $(DIR))" || { echo "reference-check: $(DIR) is not a directory"; exit 2; }
	@cd ios && TEST_RUNNER_KANAME_REFERENCE_DIR="$(abspath $(DIR))" \
		TEST_RUNNER_KANAME_REFERENCE_SHAPES="$(KANAME_REFERENCE_SHAPES)" xcodebuild \
		-workspace Kaname.xcworkspace -scheme Kaname \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
		-only-testing:KanameTests/ReferenceSetVerification test > reference-check.log 2>&1; \
		status=$$?; \
		echo; \
		grep -E '^(reference-check:|  \[| {6}\|| {6}shape of)' reference-check.log || true; \
		echo; \
		grep -q '^reference-check:' reference-check.log \
			|| { echo "reference-check: the suite did not run — nothing was measured."; status=1; }; \
		rm -f reference-check.log; \
		exit $$status

# Same pass, but describing the *shape* of any document that read nothing: digits become 9,
# letters become A/a, punctuation and spacing stay. No merchant, amount, date or account
# number can survive that, so the output is safe to paste into a bug report — which is the
# only way a layout this repository may never see can be fixed.
reference-shapes:
	@$(MAKE) reference-check DIR="$(DIR)" KANAME_REFERENCE_SHAPES=1

# The platform half of the Principle I gate: fail if any networking symbol appears on the
# statement-import path. `core-privacy-audit` cannot see Swift.
import-audit:
	./scripts/import-path-audit.sh

# --- Everything ---
lint: core-lint
	cd ios && swiftlint --strict && swift-format lint --recursive --strict Sources Tests UITests
