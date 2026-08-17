.PHONY: perf-corpus bootstrap core-test core-lint core-fmt core-privacy-audit core-xcframework ios-gen ios-test import-audit release-audit lint reference-check reference-shapes a11y-sweep

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
	@# The same trap one layer up, and it cost a false failure on 2026-08-16. The UI tests
	@# set their own *appearance* and tear it down, but nothing resets the **text size** —
	@# so a manual gate run left at `accessibility-extra-extra-extra-large` makes the two
	@# front-door contrast audits fail against a screen no test asked for. The audits are
	@# written for the default size; pin it here rather than trusting the last person to
	@# have put it back.
	@xcrun simctl ui "iPhone 16" content_size large >/dev/null 2>&1 || true
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

# The corpus the manual performance gate (T139 G9-G12) is measured against: 10,000
# transactions over 8 accounts, plus a 200-row corpus for the comparison, written as
# statement PDFs. There is no seeding hook and there will not be one (FR-077), so the only
# way a corpus reaches a device is the way a person's own data does: documents, imported
# through the picker. Every document is drawn from a proven layout signature in
# fixtures/geometry/ and read back through the shipping extractor before it is handed over.
#
#     make perf-corpus DIR=/path/to/write/it
#
# Then AirDrop 10000-rows/*.pdf to the phone and import all eight.
perf-corpus: ios-gen
	@test -n "$(DIR)" || { echo "usage: make perf-corpus DIR=/path/to/write/the/corpus"; exit 2; }
	@mkdir -p "$(abspath $(DIR))"
	@cd ios && TEST_RUNNER_KANAME_CORPUS_DIR="$(abspath $(DIR))" xcodebuild \
		-workspace Kaname.xcworkspace -scheme Kaname \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
		-only-testing:KanameTests/PerformanceCorpusGenerator test > perf-corpus.log 2>&1; \
		status=$$?; \
		echo; \
		grep -E '^perf-corpus:' perf-corpus.log || true; \
		echo; \
		grep -q '^perf-corpus:' perf-corpus.log \
			|| { echo "perf-corpus: the generator did not run - nothing was written."; status=1; }; \
		rm -f perf-corpus.log; \
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

# Prove no seeding path is in the Release binary (~16s: it builds one).
#
# Deliberately NOT folded into `import-audit`, which is a sub-second grep people run
# constantly — a 16-second build inside it is the reason somebody stops running it (019 FR-028,
# SC-014). It needs `ios/Kaname.xcworkspace`, which Tuist generates; the script says so by name
# rather than letting `xcodebuild` complain, so this target deliberately has NO `ios-gen`
# prerequisite: a gate that silently regenerates the project is a gate that can pass against a
# tree the reader is not looking at.
release-audit:
	@bash scripts/release-absence-audit.sh

# The accessibility axes a test cannot set for itself (T123, Constitution IV).
#
# `performAccessibilityAudit` runs against whatever the device is currently configured for,
# and XCUITest can set appearance and text size but NOT Increase Contrast — that one is read
# from the accessibility daemon, so neither a launch argument nor a test API reaches it. Only
# `simctl` does. This runs the front-door audit with it on, and puts the simulator back
# afterwards however the run ends.
#
# Reduce Transparency has no `simctl` control at all and stays with the manual gate, as do
# VoiceOver's announcements and the four screens behind an import.
a11y-sweep: ios-gen
	@xcrun simctl bootstatus "iPhone 16" -b >/dev/null 2>&1 || true
	@xcrun simctl uninstall "iPhone 16" in.beaconbrain.kaname >/dev/null 2>&1 || true
	@echo "a11y-sweep: Increase Contrast enabled"
	@xcrun simctl ui "iPhone 16" increase_contrast enabled >/dev/null 2>&1 || \
		{ echo "a11y-sweep: this runtime cannot set Increase Contrast — nothing was proven."; exit 1; }
	@cd ios && xcodebuild -workspace Kaname.xcworkspace -scheme Kaname \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
		-only-testing:KanameUITests test; \
		status=$$?; \
		xcrun simctl ui "iPhone 16" increase_contrast disabled >/dev/null 2>&1 || true; \
		echo "a11y-sweep: Increase Contrast restored to disabled"; \
		exit $$status

# --- Everything ---
lint: core-lint
	cd ios && swiftlint --strict && swift-format lint --recursive --strict Sources Tests UITests
