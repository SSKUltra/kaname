use std::collections::HashSet;

use kaname_core::statement::{
    au_bank, federal, federal_bank, hdfc, hdfc_bank, icici, icici_bank, iob, registry, sbi, yes,
};
use kaname_core::{
    detect_issuer, read_au_bank_statement, read_federal_bank_statement, read_federal_statement,
    read_hdfc_bank_statement, read_hdfc_statement, read_icici_bank_statement, read_icici_statement,
    read_iob_statement, read_sbi_statement, read_statement, read_yes_statement, Direction,
    DirectionSource, Issuer, LineWords, ParsedStatement, ReaderError, StatementKind, Word,
};
use serde::Deserialize;

#[derive(Deserialize)]
struct Fixture {
    lines: Vec<String>,
    full_text: String,
    #[serde(default)]
    line_words: Vec<LineWords>,
}

fn load_fixture(rel_path: &str) -> Fixture {
    let path = format!(
        "{}/../../../fixtures/{}",
        env!("CARGO_MANIFEST_DIR"),
        rel_path
    );
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("parse {path}: {e}"))
}

#[test]
fn registry_ids_are_unique_and_total() {
    let mut ids = HashSet::new();
    let mut order_keys = HashSet::new();
    for entry in registry::entries() {
        assert!(ids.insert(entry.id), "duplicate issuer id {}", entry.id);
        assert!(
            order_keys.insert((registry::kind_rank(entry.kind), entry.id)),
            "duplicate tie-break key for {}",
            entry.id
        );
    }
    assert_eq!(ids.len(), 10, "the approved registry has ten issuers");
}

#[test]
fn registry_display_names_are_non_empty() {
    for entry in registry::entries() {
        assert!(
            !entry.display_name.trim().is_empty(),
            "{} has no display name",
            entry.id
        );
    }
}

#[test]
fn registry_bank_code_matches_the_backing_reader_constant() {
    let expected = [
        ("AU_BANK", au_bank::BANK_CODE, StatementKind::BankAccount),
        (
            "FEDERAL_BANK",
            federal_bank::BANK_CODE,
            StatementKind::BankAccount,
        ),
        (
            "HDFC_BANK",
            hdfc_bank::BANK_CODE,
            StatementKind::BankAccount,
        ),
        (
            "ICICI_BANK",
            icici_bank::BANK_CODE,
            StatementKind::BankAccount,
        ),
        (
            "FEDERAL_CARD",
            federal::BANK_CODE,
            StatementKind::CreditCard,
        ),
        ("HDFC_CARD", hdfc::BANK_CODE, StatementKind::CreditCard),
        ("ICICI_CARD", icici::BANK_CODE, StatementKind::CreditCard),
        ("IOB_CARD", iob::BANK_CODE, StatementKind::CreditCard),
        ("SBI_CARD", sbi::BANK_CODE, StatementKind::CreditCard),
        ("YES_CARD", yes::BANK_CODE, StatementKind::CreditCard),
    ];
    for (id, bank_code, kind) in expected {
        let entry = registry::entries()
            .iter()
            .find(|entry| entry.id == id)
            .unwrap_or_else(|| panic!("missing registry entry {id}"));
        assert_eq!(entry.bank_code, bank_code, "{id}: bank code");
        assert_eq!(entry.kind, kind, "{id}: kind");
    }
}

#[test]
fn detect_issuer_returns_none_for_an_unclaimed_document() {
    assert_eq!(
        detect_issuer("Electricity bill\nnot a statement".to_string()),
        None
    );
}

#[test]
fn detect_issuer_is_deterministic_over_repeated_calls() {
    let fx = load_fixture("hdfc/credit_card/monthly.json");
    let first = detect_issuer(fx.full_text.clone());
    let second = detect_issuer(fx.full_text);
    assert_eq!(first, second);
}

/// Gate **G6** (FR-013, SC-004): the pre-slice recognition baseline, captured as data while
/// `main` was still unchanged. Every statement fixture in `fixtures/` resolved to exactly the
/// issuer named here before 017 widened claim matching, and must resolve to it after.
///
/// When 017 PR B renames the six card entries per FR-041–FR-043, the **right-hand column** is
/// updated to the new ids and nothing else: a row may be renamed, never removed, and no fixture
/// may change which *institution and kind* it resolves to.
const FIXTURE_ISSUER_BASELINE: &[(&str, &str)] = &[
    ("au/bank_account/savings.json", "AU_BANK"),
    ("federal/bank_account/classic.json", "FEDERAL_BANK"),
    ("federal/bank_account/fi.json", "FEDERAL_BANK"),
    ("federal/credit_card/basic.json", "FEDERAL_CARD"),
    ("hdfc/bank_account/compact.json", "HDFC_BANK"),
    ("hdfc/bank_account/detailed.json", "HDFC_BANK"),
    ("hdfc/credit_card/monthly.json", "HDFC_CARD"),
    ("hdfc/credit_card/year_end.json", "HDFC_CARD"),
    ("icici/bank_account/basic.json", "ICICI_BANK"),
    ("icici/credit_card/basic.json", "ICICI_CARD"),
    ("iob/credit_card/basic.json", "IOB_CARD"),
    ("sbi_card/credit_card/basic.json", "SBI_CARD"),
    ("yes/credit_card/basic.json", "YES_CARD"),
    ("yes/credit_card/mismatched_totals.json", "YES_CARD"),
];

#[test]
fn every_fixture_resolves_to_its_pre_slice_issuer() {
    for (rel_path, expected_id) in FIXTURE_ISSUER_BASELINE {
        let fx = load_fixture(rel_path);
        let issuer = detect_issuer(fx.full_text)
            .unwrap_or_else(|| panic!("{rel_path}: recognised before this slice, not now"));
        assert_eq!(&issuer.id, expected_id, "{rel_path}");
    }
}

/// The baseline above is only a gate if it is *total*. A statement fixture added later must be
/// added to it too, so this walks `fixtures/` and demands every document-shaped vector — anything
/// carrying a `full_text` — appear in the table.
#[test]
fn the_issuer_baseline_covers_every_statement_fixture() {
    let root = format!("{}/../../../fixtures", env!("CARGO_MANIFEST_DIR"));
    let listed: HashSet<&str> = FIXTURE_ISSUER_BASELINE
        .iter()
        .map(|(path, _)| *path)
        .collect();

    let mut found = Vec::new();
    let mut stack = vec![std::path::PathBuf::from(&root)];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).unwrap_or_else(|e| panic!("read_dir {dir:?}: {e}")) {
            let path = entry.expect("dir entry").path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|ext| ext == "json") {
                let raw = std::fs::read_to_string(&path).expect("read fixture");
                let value: serde_json::Value = serde_json::from_str(&raw).expect("parse fixture");
                if value.get("full_text").is_some() {
                    let rel = path
                        .strip_prefix(&root)
                        .expect("fixture under fixtures/")
                        .to_string_lossy()
                        .into_owned();
                    found.push(rel);
                }
            }
        }
    }

    found.sort();
    for rel in &found {
        assert!(
            listed.contains(rel.as_str()),
            "{rel} is a statement fixture but is missing from FIXTURE_ISSUER_BASELINE"
        );
    }
    assert_eq!(
        found.len(),
        FIXTURE_ISSUER_BASELINE.len(),
        "baseline lists a fixture that no longer exists"
    );
}

#[test]
fn ledger_beats_card_on_a_doubly_claimed_document() {
    let text = concat!(
        "ICICI Bank\n",
        "Statement of Transactions\n",
        "Savings Account\n"
    );
    let issuer = detect_issuer(text.to_string()).expect("ICICI ledger should be claimed");
    assert_eq!(issuer.id, "ICICI_BANK");
    assert_eq!(issuer.kind, StatementKind::BankAccount);
}

#[test]
fn ledger_wins_for_the_three_doubly_claimed_golden_fixtures() {
    for (rel_path, expected_id) in [
        ("federal/bank_account/classic.json", "FEDERAL_BANK"),
        ("federal/bank_account/fi.json", "FEDERAL_BANK"),
        ("icici/bank_account/basic.json", "ICICI_BANK"),
    ] {
        let fx = load_fixture(rel_path);
        let issuer = detect_issuer(fx.full_text).unwrap_or_else(|| panic!("{rel_path}: no issuer"));
        assert_eq!(issuer.id, expected_id, "{rel_path}");
        assert_eq!(issuer.kind, StatementKind::BankAccount, "{rel_path}");
    }
}

fn assert_dispatch_matches_legacy(
    rel_path: &str,
    issuer_id: &str,
    legacy: impl Fn(Vec<String>, String) -> ParsedStatement,
) {
    let fx = load_fixture(rel_path);
    let issuer =
        detect_issuer(fx.full_text.clone()).unwrap_or_else(|| panic!("{rel_path}: issuer"));
    assert_eq!(issuer.id, issuer_id, "{rel_path}: issuer id");
    let dispatched = read_statement(
        issuer,
        fx.lines.clone(),
        fx.full_text.clone(),
        fx.line_words.clone(),
    )
    .unwrap_or_else(|e| panic!("{rel_path}: {e}"));
    let expected = legacy(fx.lines, fx.full_text);
    assert_eq!(dispatched, expected, "{rel_path}: dispatched parse");
}

#[test]
fn read_statement_matches_icici_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "icici/credit_card/basic.json",
        "ICICI_CARD",
        read_icici_statement,
    );
}

#[test]
fn read_statement_matches_hdfc_card_reader_byte_for_byte() {
    for rel_path in [
        "hdfc/credit_card/year_end.json",
        "hdfc/credit_card/monthly.json",
    ] {
        assert_dispatch_matches_legacy(rel_path, "HDFC_CARD", |lines, text| {
            read_hdfc_statement(lines, text)
        });
    }
}

#[test]
fn read_statement_matches_sbi_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "sbi_card/credit_card/basic.json",
        "SBI_CARD",
        read_sbi_statement,
    );
}

#[test]
fn read_statement_matches_yes_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy("yes/credit_card/basic.json", "YES_CARD", |lines, text| {
        read_yes_statement(lines, text)
    });
}

#[test]
fn read_statement_matches_iob_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy("iob/credit_card/basic.json", "IOB_CARD", |lines, text| {
        read_iob_statement(lines, text)
    });
}

#[test]
fn read_statement_matches_federal_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "federal/credit_card/basic.json",
        "FEDERAL_CARD",
        read_federal_statement,
    );
}

#[test]
fn read_statement_matches_icici_bank_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "icici/bank_account/basic.json",
        "ICICI_BANK",
        |lines, text| read_icici_bank_statement(lines, text, Vec::new()),
    );
}

#[test]
fn read_statement_matches_hdfc_bank_reader_byte_for_byte() {
    for rel_path in [
        "hdfc/bank_account/compact.json",
        "hdfc/bank_account/detailed.json",
    ] {
        assert_dispatch_matches_legacy(rel_path, "HDFC_BANK", |lines, text| {
            read_hdfc_bank_statement(lines, text, Vec::new())
        });
    }
}

#[test]
fn read_statement_matches_federal_bank_reader_byte_for_byte() {
    for rel_path in [
        "federal/bank_account/classic.json",
        "federal/bank_account/fi.json",
    ] {
        assert_dispatch_matches_legacy(rel_path, "FEDERAL_BANK", |lines, text| {
            read_federal_bank_statement(lines, text, Vec::new())
        });
    }
}

#[test]
fn read_statement_matches_au_bank_reader_byte_for_byte() {
    assert_dispatch_matches_legacy("au/bank_account/savings.json", "AU_BANK", |lines, text| {
        read_au_bank_statement(lines, text, Vec::new())
    });
}

#[test]
fn read_statement_rejects_an_unknown_issuer_id() {
    let issuer = Issuer {
        id: "NO_SUCH_ISSUER".to_string(),
        display_name: "No Such Issuer".to_string(),
        bank_code: "NOPE".to_string(),
        kind: StatementKind::CreditCard,
    };
    let err = read_statement(issuer, Vec::new(), String::new(), Vec::new())
        .expect_err("unknown issuer must be rejected");
    assert_eq!(
        err,
        ReaderError::UnknownIssuer {
            id: "NO_SUCH_ISSUER".to_string()
        }
    );
}

#[test]
fn read_statement_ignores_line_words_for_card_issuers() {
    let fx = load_fixture("icici/credit_card/basic.json");
    let issuer = detect_issuer(fx.full_text.clone()).expect("issuer");
    let noisy_words = vec![LineWords {
        line_index: 0,
        words: vec![Word {
            text: "999999.99".to_string(),
            x0: 999.0,
            x1: 1000.0,
        }],
    }];
    let dispatched = read_statement(issuer, fx.lines.clone(), fx.full_text.clone(), noisy_words)
        .expect("card dispatch");
    let legacy = read_icici_statement(fx.lines, fx.full_text);
    assert_eq!(dispatched, legacy);
}

#[test]
fn read_statement_forwards_only_the_anchor_row_geometry() {
    let fx = load_fixture("icici/bank_account/basic.json");
    assert!(
        !fx.line_words.is_empty(),
        "fixture must carry synthetic line_words"
    );
    let full_text = fx
        .lines
        .iter()
        .filter(|line| !line.starts_with("Opening Balance "))
        .cloned()
        .collect::<Vec<_>>()
        .join("\n");
    let issuer = detect_issuer(full_text.clone()).expect("issuer");

    let dispatched =
        read_statement(issuer, fx.lines, full_text, fx.line_words).expect("ledger dispatch");
    let first = dispatched.lines.first().expect("first parsed row");
    assert_eq!(first.direction, Direction::Debit);
    assert_eq!(
        first.ledger.as_ref().map(|ledger| ledger.direction_source),
        Some(DirectionSource::Row1XPosition)
    );
}

/// The totality guarantee in `contracts/engine-ffi.md` §2: detection returns for *any*
/// input. The app hands the engine whatever PDFKit produced, so a document nobody
/// anticipated must end as "not recognised", never as a crashed import.
#[test]
fn detect_issuer_never_panics_on_arbitrary_input() {
    assert_eq!(
        detect_issuer(String::new()),
        None,
        "empty text claims nobody"
    );

    // Every byte value, control characters and lone-surrogate-shaped bytes included,
    // repeated past any reader's scan window.
    let byte_soup: String =
        String::from_utf8_lossy(&(0..=255u8).cycle().take(64 * 1024).collect::<Vec<u8>>())
            .into_owned();
    assert_eq!(detect_issuer(byte_soup.clone()), detect_issuer(byte_soup));

    // Multi-megabyte input: a 200-page statement's text is the realistic upper bound, and
    // a reader that scans quadratically would be found here rather than by a person.
    let huge = "Statement of account\nUPI-EXAMPLE-MERCHANT 1,234.56 Dr\n".repeat(40_000);
    assert!(huge.len() > 2 * 1024 * 1024, "input must be multi-megabyte");
    let _ = detect_issuer(huge);

    for text in [
        "\u{0}\u{1}\u{2}",
        "\u{FEFF}",
        "🧾💳🏦",
        "\u{202E}drawkcab",
        "                                        ",
        "\n\n\n\n",
    ] {
        assert!(
            detect_issuer(text.to_string()).is_none(),
            "{text:?} must claim no reader"
        );
    }
}

/// Whatever detection minted, parsing must accept — including with the geometry and the
/// lines deliberately disagreeing with each other, which is exactly what a merged-line or
/// mis-indexed extraction looks like.
#[test]
fn read_statement_never_panics_on_mismatched_lines_and_geometry() {
    let fx = load_fixture("icici/bank_account/basic.json");
    let issuer = detect_issuer(fx.full_text.clone()).expect("issuer");

    let out_of_range_geometry = vec![LineWords {
        line_index: u32::MAX,
        words: vec![Word {
            text: String::new(),
            x0: f64::NAN,
            x1: f64::NEG_INFINITY,
        }],
    }];
    assert!(read_statement(
        issuer.clone(),
        fx.lines.clone(),
        fx.full_text.clone(),
        out_of_range_geometry
    )
    .is_ok());

    // No lines at all, with the full text still claiming the issuer.
    assert!(read_statement(issuer, Vec::new(), fx.full_text, Vec::new()).is_ok());
}
