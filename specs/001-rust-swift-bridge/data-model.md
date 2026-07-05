# Phase 1 Data Model: Rust ↔ Swift Bridge

**Feature**: `001-rust-swift-bridge` | **Date**: 2026-07-05
**Derived from**: `spec.md` Key Entities + `research.md` D2/D3

This slice introduces no persistence. "Entities" here are the typed values that cross
the app ↔ engine (UniFFI) boundary and the value objects they are built from. All types
live in `core/crates/kaname-core` and are surfaced to Swift via generated bindings.

---

## Entity: Engine Version

The shared engine's build identifier, produced by the engine and displayed by the app.

| Attribute | Type (Rust) | Type (Swift) | Notes |
|-----------|-------------|--------------|-------|
| value | `String` (owned) | `String` | `env!("CARGO_PKG_VERSION")`, e.g. `"0.1.0"` |

- **Source of truth**: the engine only (FR-002). Never hardcoded in the app.
- **Validation**: MUST be non-empty (spec edge case). If empty at runtime, the app shows
  branding without a version — never a fabricated value (FR-013).
- **Determinism**: constant for a given build; identical on every call (FR-008).
- **Exposed by**: `engine_version() -> String`.

---

## Value Object: Direction (enum)

Whether money moved out of (`Debit`) or into (`Credit`) an account. Carries polarity so
amounts stay unsigned magnitudes (constitution: "polarity via Direction, never sign").

| Variant | Meaning |
|---------|---------|
| `Debit` | money out |
| `Credit` | money in |

- **Rust**: existing `enum Direction` + **add** `#[derive(uniffi::Enum)]`
  (keeps `Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize`).
- **Swift**: generated `enum Direction { case debit, credit }`.
- **FFI**: native UniFFI enum (no custom type needed).

---

## Custom Type: Money Amount (`Decimal`)

An exact base-10 monetary magnitude. **Never a floating-point number** (Principle II,
FR-010).

| Layer | Representation |
|-------|----------------|
| Rust | `rust_decimal::Decimal` |
| FFI wire | `String` (e.g. `"250.00"`, `"0"`, `"999999999.99"`) via remote `custom_type!` |
| Swift | `Foundation.Decimal` (via `uniffi.toml` custom-type mapping) |

- **Conversion**: `lower = d.to_string()`; `try_lift = s.parse::<Decimal>()`. Swift parses
  with `en_US_POSIX` locale so `.` is always the separator (determinism).
- **Validation / boundaries**: zero, very large, and high-precision (many decimal places)
  values MUST round-trip exactly (US2 scenario 3, SC-003). No rounding, no `f64`.

---

## Custom Type: Transaction Date (`NaiveDate`)

A calendar date (no time-of-day, no timezone).

| Layer | Representation |
|-------|----------------|
| Rust | `chrono::NaiveDate` |
| FFI wire | `String`, ISO-8601 `YYYY-MM-DD` via remote `custom_type!` |
| Swift | `String` (ISO-8601) — a calendar date, not a `Date` point-in-time |

- **Conversion**: `lower = format("%Y-%m-%d")`; `try_lift = parse_from_str(…, "%Y-%m-%d")`.
- **Validation**: only well-formed ISO dates are liftable; a malformed string fails lift
  (surfaced as an error, not a silent default).

---

## Entity: Transaction (Round-Trip Value)

A single normalized financial transaction — the typed, structured value that travels
app → engine → app (spec "Round-Trip Value"). Reuses the existing domain `struct`.

| Field | Type (Rust) | Type (Swift) | Round-trip behavior |
|-------|-------------|--------------|---------------------|
| `date` | `NaiveDate` | `String` (ISO-8601) | preserved exactly |
| `description` | `String` | `String` | **normalized** (whitespace-collapse + Unicode uppercase) |
| `amount` | `Decimal` | `Decimal` | preserved exactly (no float) |
| `direction` | `Direction` | `Direction` | preserved exactly |

- **Rust**: existing `struct Transaction` + **add** `#[derive(uniffi::Record)]`
  (keeps `Debug, Clone, PartialEq, Serialize, Deserialize` and the inherent
  `new` / `signed_amount` methods, which UniFFI ignores unless exported).
- **Swift**: generated `struct Transaction { let date: String; let description: String;
  let amount: Decimal; let direction: Direction }`.
- **Invariants** (asserted by the round-trip tests):
  - Output `description == normalize_description(input.description)` — proves non-constant
    engine computation crossed back (FR-005).
  - Output `amount == input.amount`, `date == input.date`, `direction == input.direction`
    — proves exact, lossless preservation (FR-004, US2 scenarios 3–4).
  - Same input ⇒ identical output every call (FR-008, SC-004).

---

## Operation: `normalize_transaction`

The deterministic typed round-trip.

- **Signature (Rust)**: `#[uniffi::export] pub fn normalize_transaction(input: Transaction) -> Transaction`
- **Signature (Swift)**: `func normalizeTransaction(input: Transaction) -> Transaction`
- **Semantics**: returns a `Transaction` whose `description` is
  `normalize_description(input.description)` and whose `date`, `amount`, `direction` equal
  the input. Pure: no clock, no locale, no network, no global mutable state.

---

## Type / boundary map (at a glance)

```text
        Rust (kaname-core)                 FFI wire            Swift (KanameCore)
        ------------------                 --------            ------------------
engine_version() -> String                 string              engineVersion() -> String
Direction { Debit, Credit }   uniffi::Enum  (tag)              enum Direction {debit,credit}
Decimal (rust_decimal)        custom_type   String  ───────►   Decimal (Foundation)
NaiveDate (chrono)            custom_type   String  ───────►   String  (ISO-8601)
Transaction { date, desc,     uniffi::Record record            struct Transaction {…}
              amount, dir }
normalize_transaction(Transaction) -> Transaction              normalizeTransaction(_:)
```

**No database, no migrations, no state transitions** in this feature (storage arrives P2+).
