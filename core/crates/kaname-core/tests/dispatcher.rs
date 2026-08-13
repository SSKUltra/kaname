use std::collections::{HashMap, HashSet};

use kaname_core::statement::{
    au_bank, claim, federal, federal_bank, hdfc, hdfc_bank, icici, icici_bank, iob, registry, sbi,
    yes,
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

/// **Gate G1** (FR-050, FR-051): a bank-level claim is only honest while its institution has
/// exactly one card.
///
/// Every card reader shipped today claims at bank granularity — `["ICICI Bank"]`,
/// `["SBI Card", …]`, `["YES BANK"]` — so per-product identification is currently correct by
/// *uniqueness*, not by evidence. The rename must not be allowed to disguise that. Adding an
/// `HDFC_INFINIA_CARD` beside `HDFC_SWIGGY_CARD` fails here until both can prove which
/// product they are.
#[test]
fn two_cards_from_one_institution_must_both_prove_their_product() {
    let mut cards_per_institution: HashMap<&str, Vec<&registry::ReaderEntry>> = HashMap::new();
    for entry in registry::entries() {
        if entry.kind == StatementKind::CreditCard {
            cards_per_institution
                .entry(entry.bank_code)
                .or_default()
                .push(entry);
        }
    }

    for (bank_code, cards) in cards_per_institution {
        if cards.len() < 2 {
            continue;
        }
        for card in cards {
            assert_eq!(
                card.evidence,
                registry::ClaimEvidence::ProductProven,
                "{bank_code} has {} card entries, so {} must identify its product from the \
                 document rather than rely on being the only one",
                cards_per_institution_len(bank_code),
                card.id
            );
        }
    }
}

fn cards_per_institution_len(bank_code: &str) -> usize {
    registry::entries()
        .iter()
        .filter(|e| e.kind == StatementKind::CreditCard && e.bank_code == bank_code)
        .count()
}

/// **Gate G2** (FR-048): two product-proven cards claiming one document is a loud failure,
/// never a silent tie-break.
#[test]
fn no_fixture_is_claimed_by_two_product_proven_cards() {
    for (rel_path, _) in FIXTURE_ISSUER_BASELINE {
        let fx = load_fixture(rel_path);
        let proven: Vec<&str> = registry::claimants(&fx.full_text)
            .iter()
            .filter(|e| {
                e.kind == StatementKind::CreditCard
                    && e.evidence == registry::ClaimEvidence::ProductProven
            })
            .map(|e| e.id)
            .collect();
        assert!(
            proven.len() <= 1,
            "{rel_path} is claimed as a proven product by {proven:?}"
        );
    }
}

/// **Gate G3** (FR-052): one naming convention, and the institution prefix *is* the
/// `bank_code`. It is what makes G1's "two cards share an institution" check visible at a
/// glance.
#[test]
fn every_registry_id_follows_the_naming_convention() {
    for entry in registry::entries() {
        let expected_prefix = match entry.kind {
            StatementKind::BankAccount => format!("{}_BANK", entry.bank_code),
            StatementKind::CreditCard => format!("{}_", entry.bank_code),
        };
        match entry.kind {
            StatementKind::BankAccount => assert_eq!(
                entry.id, expected_prefix,
                "a bank account is named <INSTITUTION>_BANK"
            ),
            StatementKind::CreditCard => {
                assert!(
                    entry.id.starts_with(&expected_prefix) && entry.id.ends_with("_CARD"),
                    "{} is not <INSTITUTION>_<PRODUCT>_CARD for {}",
                    entry.id,
                    entry.bank_code
                );
                let product = entry
                    .id
                    .trim_start_matches(&expected_prefix)
                    .trim_end_matches("_CARD");
                assert!(!product.is_empty(), "{} names no product", entry.id);
            }
        }
        assert!(
            entry
                .id
                .chars()
                .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_'),
            "{} is not upper snake case",
            entry.id
        );
    }
}

/// **Gate G4** (FR-046, FR-053): `bank_code` answers "which institution", never "which
/// product" or "which kind". `sbi.rs` shipped `"SBI_CARD"` in that field; this is what keeps
/// it from coming back.
#[test]
fn no_bank_code_carries_a_product_or_a_kind() {
    for entry in registry::entries() {
        for forbidden in ["_CARD", "_BANK", "CARD", "BANK"] {
            assert!(
                !entry.bank_code.contains(forbidden),
                "{} has bank_code {:?}, which names something other than an institution",
                entry.id,
                entry.bank_code
            );
        }
    }
}

/// **Gate G5** (FR-016): a reader claiming a document of the other kind is a defect — with
/// three shipped exceptions, and no more.
///
/// A card marker like `Federal Bank` matches that bank's *ledger* too. `kind_rank` resolves
/// all three correctly today, so this is noise rather than a wrong answer; what must not
/// happen is the set quietly growing. Naming it is what turns "we know about these" into a
/// gate.
///
/// A **test**, deliberately never a runtime rule: research R10 found no evidence of a reader
/// mis-claiming across kinds in a way that changes an answer, and a runtime guard risks a
/// reader declining a statement of its own kind — a worse failure than the one it prevents.
const KNOWN_CROSS_KIND_CLAIMS: &[(&str, &str)] = &[
    ("federal/bank_account/classic.json", "FEDERAL_SCAPIA_CARD"),
    ("federal/bank_account/fi.json", "FEDERAL_SCAPIA_CARD"),
    ("icici/bank_account/basic.json", "ICICI_AMAZONPAY_CARD"),
];

#[test]
fn no_reader_claims_a_document_of_the_other_kind() {
    let mut found = Vec::new();
    for (rel_path, _) in FIXTURE_ISSUER_BASELINE {
        let fixture_kind = if rel_path.contains("bank_account") {
            StatementKind::BankAccount
        } else {
            StatementKind::CreditCard
        };
        let fx = load_fixture(rel_path);

        // Whatever else claims it, the answer the person is given must be of the right kind.
        let resolved =
            detect_issuer(fx.full_text.clone()).unwrap_or_else(|| panic!("{rel_path}: no issuer"));
        assert_eq!(
            resolved.kind, fixture_kind,
            "{rel_path} resolved to the wrong kind"
        );

        for entry in registry::claimants(&fx.full_text) {
            if entry.kind != fixture_kind {
                found.push((*rel_path, entry.id));
            }
        }
    }

    found.sort_unstable();
    let mut known = KNOWN_CROSS_KIND_CLAIMS.to_vec();
    known.sort_unstable();
    assert_eq!(
        found, known,
        "the set of cross-kind claims changed; a new one is a defect, and a removed one is \
         progress worth recording here"
    );
}

/// FR-048: candidates order by `(kind_rank, evidence_rank, id)`.
///
/// `evidence_rank` is inserted **after** `kind_rank` precisely so the three doubly-claimed
/// golden fixtures keep resolving to the ledger — the specificity rule replaces an
/// alphabetical accident between cards, and changes nothing between kinds (FR-013).
#[test]
fn a_proven_product_outranks_a_bank_level_claim_but_never_outranks_a_ledger() {
    assert!(
        registry::evidence_rank(registry::ClaimEvidence::ProductProven)
            < registry::evidence_rank(registry::ClaimEvidence::BankLevel)
    );
    assert!(
        registry::kind_rank(StatementKind::BankAccount)
            < registry::kind_rank(StatementKind::CreditCard)
    );

    // The ordering key a ledger presents beats every card's, whatever either can prove.
    let ledger_key = (
        registry::kind_rank(StatementKind::BankAccount),
        registry::evidence_rank(registry::ClaimEvidence::BankLevel),
    );
    let proven_card_key = (
        registry::kind_rank(StatementKind::CreditCard),
        registry::evidence_rank(registry::ClaimEvidence::ProductProven),
    );
    assert!(ledger_key < proven_card_key);
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
            "FEDERAL_SCAPIA_CARD",
            federal::BANK_CODE,
            StatementKind::CreditCard,
        ),
        (
            "HDFC_SWIGGY_CARD",
            hdfc::BANK_CODE,
            StatementKind::CreditCard,
        ),
        (
            "ICICI_AMAZONPAY_CARD",
            icici::BANK_CODE,
            StatementKind::CreditCard,
        ),
        ("IOB_RUPAY_CARD", iob::BANK_CODE, StatementKind::CreditCard),
        (
            "SBI_CASHBACK_CARD",
            sbi::BANK_CODE,
            StatementKind::CreditCard,
        ),
        ("YES_KIWI_CARD", yes::BANK_CODE, StatementKind::CreditCard),
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

/// **Gate G7** (FR-014): a bank named inside somebody's spending is not the bank that issued
/// the statement.
///
/// Measured, not hypothetical: a real AU savings statement carries the literal `HDFC` inside
/// a UPI narration, and `hdfc_bank::CLAIM_ALL` is exactly `["HDFC"]`. Before 017 that was held
/// off only by the document failing every one of HDFC's `CLAIM_ANY` markers — and
/// whitespace-insensitive matching widens all of them at once. This is the fence that makes
/// the widening safe, which is why it ships in the same PR.
#[test]
fn a_bank_named_in_a_narration_does_not_claim_the_statement() {
    let text = concat!(
        "AU Small Finance Bank\n",
        "Savings Account Details\n",
        "www.aubank.in\n",
        "Date Narration Withdrawal Amt. Deposit Amt. Balance\n",
        "01/04/2026 UPI-PAYEE-HDFC-BANK-0001 5,000.00 95,000.00\n",
        "02/04/2026 UPI-HDFC-STATEMENTOF ACCOUNT-0002 1,000.00 94,000.00\n",
    );

    let claimants: Vec<&str> = registry::claimants(text)
        .iter()
        .map(|entry| entry.id)
        .collect();
    assert_eq!(
        claimants,
        vec!["AU_BANK"],
        "only the issuer whose own header identifies it may claim the document"
    );
    assert_eq!(
        detect_issuer(text.to_string()).map(|i| i.id).as_deref(),
        Some("AU_BANK")
    );
}

/// The same hazard where it would actually change the answer.
///
/// `HDFC_BANK` sorts before `ICICI_BANK`, so an HDFC claim on an ICICI document does not
/// merely add noise — it wins, and the person is told their ICICI savings statement is an
/// HDFC one. The column header `Withdrawal Amt.` is ordinary on any ledger, and it is
/// `hdfc_bank::CLAIM_ANY`'s first marker once whitespace stops counting.
#[test]
fn a_ledger_is_not_stolen_by_another_bank_named_in_its_rows() {
    let text = concat!(
        "ICICI Bank\n",
        "Statement of Transactions in Savings Account\n",
        "Date Particulars Withdrawal Amt. Deposit Amt. Balance\n",
        "01/04/2026 UPI/HDFC/PAYMENT/0001 5,000.00 95,000.00\n",
    );

    let issuer = detect_issuer(text.to_string()).expect("the ICICI ledger is claimed");
    assert_eq!(issuer.id, "ICICI_BANK");
    assert!(
        !registry::claimants(text)
            .iter()
            .any(|entry| entry.id == "HDFC_BANK"),
        "HDFC must not claim a document that only mentions it inside a transaction row"
    );
}

/// **Gate G7, second case** (FR-047): a card statement is identified by its title, not by
/// where its holder shops.
///
/// The measured HDFC co-brand statement contains `Swiggy` roughly forty times inside merchant
/// descriptions. Product identification (PR B) matches the header region for exactly this
/// reason, so the region itself has to hold the line first.
#[test]
fn a_brand_repeated_in_the_spending_does_not_identify_the_card() {
    let mut lines = vec![
        "HDFC Bank Credit Card".to_string(),
        "Statement for the period 01/04/2026 to 30/04/2026".to_string(),
    ];
    for day in 1..=40 {
        lines.push(format!(
            "{:02}/04/2026 SWIGGY BANGALORE 4,32{:02}.10",
            (day % 28) + 1,
            day % 10
        ));
    }
    let spending_only = lines.join("\n");

    assert!(
        !claim::header_region(&spending_only).contains("swiggy"),
        "forty purchases are evidence of where someone eats, not of which card they hold"
    );

    let mut titled = lines.clone();
    titled[0] = "Swiggy HDFC Bank Credit Card".to_string();
    assert!(
        claim::header_region(&titled.join("\n")).contains("swiggy"),
        "the title line is where a product may be claimed"
    );

    // Either way it is still an HDFC card: the widening changes what may be *proven*, never
    // what is recognised.
    for text in [spending_only, titled.join("\n")] {
        assert_eq!(
            detect_issuer(text).map(|i| i.id).as_deref(),
            Some("HDFC_SWIGGY_CARD")
        );
    }
}

/// The literals in `hdfc_bank::CLAIM_ANY` — `WithdrawalAmt`, `Statementof account` — are
/// spellings a *different* extractor produced (research R7). Matching a document against the
/// spacing one extractor happened to emit was always the wrong contract.
#[test]
fn a_marker_matches_whatever_spacing_the_extractor_produced() {
    for header in [
        "Date Narration WithdrawalAmt. DepositAmt. ClosingBalance",
        "Date Narration Withdrawal Amt. Deposit Amt. Closing Balance",
    ] {
        for title in ["Statementof account", "Statement of account"] {
            let text = format!("HDFC BANK LIMITED\n{title}\n{header}\n");
            let issuer = detect_issuer(text.clone())
                .unwrap_or_else(|| panic!("not claimed: {title} / {header}"));
            assert_eq!(issuer.id, "HDFC_BANK", "{title} / {header}");
        }
    }
}

/// US2 scenario 3: a header phrase printed as two columns, rejoined by the extractor with a
/// single space, still identifies the document.
#[test]
fn a_header_phrase_split_across_columns_still_resolves() {
    for spelling in [
        "Statement of Transactions",
        "Statement of  Transactions",
        "Statementof Transactions",
        "Statement ofTransactions",
    ] {
        let text = format!("ICICI Bank\n{spelling}\nSavings Account\n");
        let issuer = detect_issuer(text).unwrap_or_else(|| panic!("not claimed: {spelling}"));
        assert_eq!(issuer.id, "ICICI_BANK", "{spelling}");
    }
}

/// FR-014: the widening may make an existing claim easier to satisfy. It may never invent one.
#[test]
fn a_document_nobody_claimed_is_still_unclaimed() {
    for text in [
        "Electricity bill\nnot a statement",
        "TAX INVOICE\nInvoice No 42\nTotal 1,234.56\n",
        "Boarding Pass\nSeat 14A\n",
        "",
    ] {
        assert!(
            registry::claimants(text).is_empty(),
            "nothing should claim: {text:?}"
        );
        assert_eq!(detect_issuer(text.to_string()), None, "{text:?}");
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
    ("federal/credit_card/basic.json", "FEDERAL_SCAPIA_CARD"),
    ("hdfc/bank_account/compact.json", "HDFC_BANK"),
    ("hdfc/bank_account/detailed.json", "HDFC_BANK"),
    ("hdfc/credit_card/monthly.json", "HDFC_SWIGGY_CARD"),
    ("hdfc/credit_card/year_end.json", "HDFC_SWIGGY_CARD"),
    ("icici/bank_account/basic.json", "ICICI_BANK"),
    ("icici/credit_card/basic.json", "ICICI_AMAZONPAY_CARD"),
    ("iob/credit_card/basic.json", "IOB_RUPAY_CARD"),
    ("sbi_card/credit_card/basic.json", "SBI_CASHBACK_CARD"),
    ("yes/credit_card/basic.json", "YES_KIWI_CARD"),
    ("yes/credit_card/mismatched_totals.json", "YES_KIWI_CARD"),
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
        "ICICI_AMAZONPAY_CARD",
        read_icici_statement,
    );
}

#[test]
fn read_statement_matches_hdfc_card_reader_byte_for_byte() {
    for rel_path in [
        "hdfc/credit_card/year_end.json",
        "hdfc/credit_card/monthly.json",
    ] {
        assert_dispatch_matches_legacy(rel_path, "HDFC_SWIGGY_CARD", |lines, text| {
            read_hdfc_statement(lines, text)
        });
    }
}

#[test]
fn read_statement_matches_sbi_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "sbi_card/credit_card/basic.json",
        "SBI_CASHBACK_CARD",
        read_sbi_statement,
    );
}

#[test]
fn read_statement_matches_yes_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "yes/credit_card/basic.json",
        "YES_KIWI_CARD",
        read_yes_statement,
    );
}

#[test]
fn read_statement_matches_iob_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "iob/credit_card/basic.json",
        "IOB_RUPAY_CARD",
        read_iob_statement,
    );
}

#[test]
fn read_statement_matches_federal_card_reader_byte_for_byte() {
    assert_dispatch_matches_legacy(
        "federal/credit_card/basic.json",
        "FEDERAL_SCAPIA_CARD",
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
