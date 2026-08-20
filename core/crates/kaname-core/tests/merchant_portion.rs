//! **P1–P6** — the derived merchant portion (FR-027, FR-027a–FR-027e).
//!
//! What is remembered is about the *merchant*, not about the one transaction. A memory formed
//! from the whole normalized narration of a UPI payment matches exactly one row forever, and
//! telling a person the app learned something when it learned nothing is the failure SC-008
//! names. **P2** is the assertion that catches it.
//!
//! Every narration here is synthetic. There is no real VPA, no real UPI handle and no real
//! account number in this repository (Constitution Principle I) — which is also the limit of
//! what this file can prove (research R16): it establishes that the rule is deterministic and
//! stable across the shapes we have, not that it is adequate against the real diversity of
//! Indian narrations.

use kaname_core::merchant::merchant_portion;
use serde::Deserialize;

#[derive(Deserialize)]
struct Fixture {
    cases: Vec<Case>,
}

#[derive(Deserialize)]
struct Case {
    narration: String,
    /// `None` in the file is a JSON `null` — the FR-027d verdict, not a missing field.
    expected_portion: Option<String>,
    covers: String,
}

fn load_fixture() -> Fixture {
    let path = format!(
        "{}/../../../fixtures/categorization/merchant_portion.json",
        env!("CARGO_MANIFEST_DIR")
    );
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("parse {path}: {e}"))
}

/// **P1** — every case in the fixture, driven from the file so that adding a case adds an
/// assertion (FR-027e).
#[test]
fn every_fixture_case_derives_its_recorded_portion() {
    let fixture = load_fixture();
    assert!(
        fixture.cases.len() >= 30,
        "the fixture is meant to cover every branch of the rule; found {} cases",
        fixture.cases.len()
    );
    for case in &fixture.cases {
        assert_eq!(
            merchant_portion(&case.narration),
            case.expected_portion,
            "{:?} ({})",
            case.narration,
            case.covers
        );
    }
}

/// **P2** 🚨 — the four `UPI-SWIGGY-*` shapes differ only by a per-transaction reference and
/// must collapse to **one** portion. This is SC-008 stated as an assertion: a memory that can
/// only ever match the row it came from has taught nothing, and the app would have said it
/// learned something.
#[test]
fn shapes_differing_only_by_a_reference_collapse_to_one_portion() {
    let shapes = [
        "UPI-SWIGGY-123456",
        "UPI-SWIGGY-1",
        "UPI-SWIGGY",
        "UPI-SWIGGY-RRN1234",
    ];
    let portions: Vec<Option<String>> = shapes.iter().map(|s| merchant_portion(s)).collect();
    assert_eq!(
        portions[0],
        Some("swiggy".to_string()),
        "the reference must not survive into the portion"
    );
    for (shape, portion) in shapes.iter().zip(&portions) {
        assert_eq!(portion, &portions[0], "{shape} derived a different portion");
    }
}

/// **P3** — every FR-027d case yields no portion. The app forms no memory and says so, rather
/// than remembering `thank you`.
#[test]
fn a_narration_with_no_shop_in_it_yields_nothing() {
    for narration in [
        "ATM CASH WITHDRAWAL",
        "CC PAYMENT RECEIVED",
        "4262 BBPS Payment received",
        "ONLINE TRF - PYMT RECD - THANK YOU",
        "PAYMENT RECEIVED BBPS - Ref No: RT0001",
        "TO ECM/600000000001 TFR",
    ] {
        assert_eq!(merchant_portion(narration), None, "{narration:?}");
    }
}

/// **P4** — the degenerate inputs, which must return `None` rather than panic or return an
/// empty string (FR-034: a transaction with an unreadable description is still correctable).
#[test]
fn degenerate_input_yields_nothing_without_panicking() {
    for narration in ["", "   ", "\t\n", "-----", "778899", "RRN1234"] {
        assert_eq!(merchant_portion(narration), None, "{narration:?}");
    }
}

/// **P5** — research R15's three priced limitations, asserted **as they actually behave**. A
/// fixture that encodes a rule's known weaknesses is what tells the next person when they
/// change; a fixture that quietly asserts the desired behaviour hides them until a person is
/// looking at the wrong category.
#[test]
fn r15_limitations_behave_as_recorded() {
    // R15 (1) — `NARRATION_LEADING_PREFIX` matches `NEFT/` but not `NEFT-` (dedup.rs:44), so
    // the channel prefix is never stripped, and `n123` carries three digits — under the
    // four-digit rule. Fixing it means editing `normalize_narration`, which Q2's answer B
    // refused: de-duplication depends on that function.
    assert_eq!(
        merchant_portion("NEFT-N123-EMPLOYER PRIVATE LIMITED-SALARY"),
        Some("n123 employer".to_string())
    );

    // R15 (2) — a merchant whose own name carries four or more digits is discarded, leaving an
    // over-broad location. This is the dangerous direction, and it is the price of the
    // four-digit rule catching `rt0001`.
    assert_eq!(
        merchant_portion("MTR1924 LALBAGH"),
        Some("lalbagh".to_string())
    );

    // R15 (3) — the same merchant on two channels does not unify, because FR-027b's matching is
    // exact equality. A person who uses one shop through both UPI and card teaches the app
    // twice. Deliberate: prefix or fuzzy matching would make "what will this match?"
    // undecidable from what the person was shown.
    let upi = merchant_portion("UPI-SWIGGY-123456");
    let pos = merchant_portion("POS SWIGGY BANGALORE RRN1234");
    assert_eq!(upi, Some("swiggy".to_string()));
    assert_eq!(pos, Some("swiggy bangalore".to_string()));
    assert_ne!(upi, pos, "R15 (3) has changed — the two channels now unify");
}

/// **P6** — the derivation is **additive** (FR-027c). `dedup::normalize_narration` is called,
/// not changed, so the cross-source de-duplication fixture still passes **unedited**: the
/// narrations below are its own, and their normalization is what the dedup layer keys on.
#[test]
fn normalize_narration_did_not_move_underneath_the_derivation() {
    use kaname_core::normalize_narration;

    // Verbatim from `fixtures/dedup/cross_source/basic.json`, whose expectations are unchanged.
    assert_eq!(normalize_narration("Swiggy Bangalore"), "swiggy bangalore");
    assert_eq!(
        normalize_narration("swiggy   bangalore"),
        "swiggy bangalore"
    );
    assert_eq!(normalize_narration("acme corp"), "acme corp");
    assert_eq!(normalize_narration("acme corporation"), "acme corporation");
    assert_eq!(normalize_narration("uber"), "uber");
    assert_eq!(normalize_narration("netflix"), "netflix");

    // And the shapes the derivation leans on hardest, so a change to either regex is caught
    // here rather than three files away.
    assert_eq!(normalize_narration("UPI-SWIGGY-RRN1234"), "swiggy-");
    assert_eq!(
        normalize_narration("POS SWIGGY BANGALORE"),
        "swiggy bangalore"
    );
}
