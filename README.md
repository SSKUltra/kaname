# Kaname

> **要 — the key to your money.** A privacy-first, local-first personal finance app for India.
> By [BeaconBrain](https://beaconbrain.in).

Kaname keeps your financial life in one place **on your device**. Import your bank and
credit-card statements, and Kaname parses, categorizes, de-duplicates and reconciles them
— with **no data ever leaving your phone** for the free, core experience.

This repository is the **open-source iOS client** (Apache-2.0). Premium/cloud features
(one-click Account Aggregator sync, broker/mutual-fund import, cross-device sync, AI
assist) are **server-gated** and live in a separate closed backend — an open-core model.

## Why local-first?
- **Privacy by design.** Your statements and transactions are processed on-device and
  stored encrypted (SQLCipher; key in the iOS Keychain / Secure Enclave).
- **You own your data.** No account required to use the core app.
- **Free = DIY, Paid = convenience.** Free users self-serve (PDF uploads, bring-your-own
  AI). Paid users get one-click aggregation and recurring auto-updates.

## Repository layout
```
kaname/
├── core/          # Rust workspace — the shared engine (parse/categorize/dedup/reconcile)
│   └── crates/kaname-core/
├── ios/           # SwiftUI app (Tuist-managed)
│   ├── Sources/
│   └── Tests/
├── fixtures/      # Golden test vectors ported from the web engine (parity)
├── docs/          # Product & engineering docs (kaname-ios-plan.md)
├── .specify/      # GitHub Spec Kit — spec-driven development workflow
└── .github/       # CI, Copilot instructions, Spec Kit prompts/agents
```

### Architecture at a glance
- **Shared Rust core** (`kaname-core`) holds all deterministic finance logic and is reused
  across platforms (iOS now; Android/desktop later) via **UniFFI** bindings.
- **Native SwiftUI UI**, following the latest HIG.
- **PDF text extraction is native** (iOS PDFKit extracts lines + word x-positions) and
  feeds the Rust parser — the core never embeds a PDF engine. Money always uses `Decimal`.

## Getting started
Prerequisites: macOS + Xcode 16+, Rust (stable), [Tuist](https://tuist.dev), SwiftLint,
swift-format.

```bash
make bootstrap     # install Rust + Tuist + SwiftLint + swift-format (idempotent)

# Rust core
make core-test          # cargo test (unit + golden-fixture parity harness)
make core-lint          # cargo fmt --check + clippy -D warnings
make core-privacy-audit # fail if any networking crate is in the shipped deps (Principle I)

# iOS app
make core-xcframework  # build the Rust engine → KanameCoreFFI.xcframework + Swift bindings
make ios-gen       # core-xcframework + tuist generate  →  Kaname.xcworkspace
make ios-test      # generate + xcodebuild test on a simulator
make lint          # core + Swift lint/format checks
```

Open `ios/Kaname.xcworkspace` in Xcode after `make ios-gen`. The Rust↔Swift bridge
(UniFFI) is detailed in
[`specs/001-rust-swift-bridge/quickstart.md`](specs/001-rust-swift-bridge/quickstart.md);
the first on-device statement parser (ICICI credit card) in
[`specs/002-icici-cc-parser/quickstart.md`](specs/002-icici-cc-parser/quickstart.md).

## Development workflow
We use **GitHub Spec Kit** for spec-driven development. For a new feature, run the
Copilot prompts in order: `speckit.specify` → `speckit.plan` → `speckit.tasks` →
`speckit.implement`. Project rules live in
[`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## License
[Apache-2.0](LICENSE). See [`NOTICE`](NOTICE).
