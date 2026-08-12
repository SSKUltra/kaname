# Contract — Platform (Swift) seams for `016-statement-import-vertical`

The iOS-side interfaces this slice introduces, all in a new `ios/Sources/Import/`. Nothing
here contains a bank name, a bank list, or a per-bank branch (FR-012, SC-010).

---

## 1. `StatementTextExtractor` — the PDFKit seam (FR-005 … FR-009)

```swift
/// Turns a picked PDF into the ONLY view of the document the engine ever gets.
/// A protocol so the pipeline is testable without a real file, and so `import PDFKit`
/// appears in exactly one type.
protocol StatementTextExtractor {
    func extract(from url: URL, password: String?) throws -> ExtractedText
}

struct ExtractedText {
    let lines: [String]
    let fullText: String
    let lineWords: [LineWords]   // engine type; sparse; may be empty
}

enum ExtractionFailure: Error, Equatable {
    case notAPDF            // PDFDocument(url:) == nil            → FR-009
    case passwordRequired   // doc.isLocked                        → FR-007
    case wrongPassword      // unlock(withPassword:) == false      → FR-007
    case noExtractableText  // opens, every page's text is blank   → FR-006
    case unreadable         // security-scoped access / read error → FR-002, US3 §7
}

struct PDFKitStatementTextExtractor: StatementTextExtractor { … }
```

### Required behaviour

| Rule | Why |
|---|---|
| Wrap the **whole** extraction in `startAccessingSecurityScopedResource()` / `defer { stopAccessing… }`, covering success, throw and cancellation | FR-002 |
| `startAccessing…` returning `false` ⇒ `.unreadable`, never a crash or a silent no-op | US3 §7 |
| Prompt on **`doc.isLocked`**, never on `doc.isEncrypted` | an empty/owner-password PDF auto-unlocks in PDFKit; keying on `isLocked` satisfies the "don't prompt pointlessly" edge case for free |
| `password` is a parameter only — never a stored property, `@State`, Keychain item, store row, or log line; the prompt's binding is cleared in `onDisappear` | FR-008 |
| Distinguish `.noExtractableText` from "unrecognized issuer" | FR-006 — they are different messages and different causes |
| Never copy the file; read into memory only | FR-004 |
| Log nothing derived from document content | FR-042 |

### Producing the three outputs

- `fullText` — concatenated `PDFPage.string`, page-separated by `\n`.
- `lines` — `fullText` split on newlines. **Do not reshape**: the ten shipped readers are
  fixture-locked against exactly this contract.
- `lineWords` — per line, whitespace-split into words; each word's character range located in
  the page string and mapped through `PDFPage.characterBounds(at:)`; `x0` = `minX` of the
  first character, `x1` = `maxX` of the last. **Page 1 only** by default — it is the only page
  whose rows the ledger anchor bootstrap can need, and it bounds cost on a 200-page statement
  (SC-008).
- **PDFKit hazard**: `PDFPage.string` indices and `characterBounds(at:)` indices can drift on
  documents with ligatures or unusual encodings. Bounds-check every index; on any mismatch,
  emit **no** `LineWords` entry for that line. Per research R5 the engine then falls back to
  `Row1Provisional` → `NeedsReview` — an honest "we're not sure", never a wrong direction.

---

## 2. `ImportService` — the pipeline actor (FR-031, FR-032, FR-036, FR-038)

```swift
actor ImportService {
    private var inFlight: Task<ImportSummary, Error>?

    /// Runs the whole vertical off the main thread. Throws `ImportFailure`.
    func run(url: URL, password: String?, onStage: @Sendable (ImportStage) -> Void)
        async throws -> ImportSummary
}
```

### Stage order and cancellation checkpoints

```text
[✓] reading      → StatementTextExtractor.extract
[✓] identifying  → detectIssuer(fullText:)        → nil ⇒ .unrecognizedIssuer (FR-013)
[✓] parsing      → readStatement(issuer:lines:fullText:lineWords:)
[✓] checking     → issuer.kind == .bankAccount ? checkBalanceChain : reconcileStatement
[✓] resolving    → listAccounts() filtered on (bankCode, isCreditCard, last4)   (FR-021/024)
 ██  saving      → store.importStatement(request:)   ATOMIC, uncancellable  ██
[✓] categorizing → (folded into importStatement)
    summary
```

`[✓]` = `try Task.checkCancellation()`. All slow work (extraction, parsing) precedes the
single write, so "cancel within 2 seconds" (SC-008) is met without ever leaving partial data
(FR-031): there is exactly one write and SQLite makes it all-or-nothing.

### Rules

| Rule | Why |
|---|---|
| `inFlight != nil` ⇒ reject a second `run` | FR-032 (double-tap Import) |
| The `Task` is owned by the actor, not a view | backgrounding must not cancel it (US6 §4) |
| Every thrown error is mapped to an `ImportFailure` case **at the actor boundary** | no `StoreError`/`ReaderError` text ever reaches the UI (FR-034, SC-007) |
| No `URLSession`, no networking symbol, anywhere on this path | FR-041 (non-negotiable, Constitution I) |
| No `Double`/`Float` anywhere on this path | FR-028 |

### Account resolution is data comparison, not branching

```swift
let candidates = try store.listAccounts().filter {
    $0.bankCode == issuer.bankCode
        && $0.isCreditCard == (issuer.kind == .creditCard)
}
```

The app compares two values the engine handed it. It contains no bank name and no bank list,
so FR-012 and SC-010 hold. `last4 == nil` with zero or ≥2 candidates ⇒ ask the person
(FR-024) — never guess.

---

## 3. UI surfaces

| View | Role | Material (per `swiftui-liquid-glass`) |
|---|---|---|
| `ImportEmptyStateView` | what Kaname does + the privacy promise + one primary action (FR-039) | `Button(…).buttonStyle(.glassProminent)` in `.safeAreaInset(edge: .bottom)` — floating CTA, the screen's single prominent element |
| `ImportProgressView` | stage text + `ProgressView` + Cancel (FR-037, FR-038) | `GlassEffectContainer(spacing:)`; `.glassEffect(.regular.interactive(), in: .capsule)` applied **after** padding/frame; `.interactive()` is honest because Cancel is tappable |
| `ImportSummaryView` | account, period, counts, warnings (FR-033, FR-035) | presented as a `.sheet` — system chrome gets glass **for free**, not re-skinned. **Figure rows are opaque, never glassed** (FR-047) |
| `AccountPickerView` | the FR-024 disambiguation | standard `List` — dense rows, not glassed |
| `PasswordPromptView` | FR-007 | standard `.alert` with a `SecureField` |

### Non-negotiable UI rules

- **No `#available(iOS 26, *)`, no fallback branch, no `.ultraThinMaterial`, no hand-rolled
  blur** — anywhere. Deployment target is iOS 26.0 (`ios/Project.swift`, all three targets).
- Every count and amount uses `.monospacedDigit()` (FR-045).
- Dense rows of numbers are **never** glassed (FR-047).
- A debit/credit colour signal never sits on tinted glass. The summary reports *counts*, not
  signed amounts, so this holds structurally — if a net figure is ever added it belongs on the
  opaque rows.
- Meaning is never carried by colour or material alone: the integrity warning is icon **plus**
  colour **plus** text (FR-046).
- At most one tinted/prominent element per screen (the Import CTA).
- Dynamic Type through the largest accessibility sizes, Dark Mode, and full VoiceOver with
  meaningful labels on every control, count and warning (FR-044, SC-009).

### Message discipline (FR-034, SC-007)

Every user-facing string is a hand-written sentence. No interpolated error, no code, no
`bank_code`, no reader name, no `localizedDescription`. The **only** engine-supplied string
allowed on screen is `Issuer.display_name` — which is user-facing data by design (FR-033).

---

## 4. Project changes

```swift
// ios/Project.swift — the "Kaname" target
.sdk(name: "PDFKit", type: .framework)
```

A first-party Apple system framework: no third-party code, no network I/O, nothing added to
the Rust crate graph the privacy-egress audit inspects. It is the platform extraction engine
the constitution itself names (Principle II).

`ios/Sources/RootView.swift` — the engine-version placeholder — is replaced by the real flow
(empty state → import → summary), keeping the engine version reachable if desired.
