use crate::ffi::{Issuer, ReaderError, StatementKind};
use crate::statement::base::{LineWords, ParsedStatement};
use crate::statement::claim::Regions;
use crate::statement::{au_bank, federal, federal_bank, hdfc, hdfc_bank, icici, icici_bank, iob};
use crate::statement::{ledger_reader, line_reader, sbi, yes};

/// How strongly a reader's claim identifies what it claims.
///
/// A card is registered per **card product**, but most statements only ever name their
/// issuing bank — so most entries are correct today by *uniqueness*, not by evidence. Saying
/// so out loud is what lets the registry refuse a second card for an institution whose first
/// one cannot prove which product it is (FR-050, FR-051).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ClaimEvidence {
    /// The statement names the product in its own title block.
    ProductProven,
    /// The statement names only its institution; the product name is a display label.
    BankLevel,
}

/// One reader registered with the dispatcher.
#[derive(Debug)]
pub struct ReaderEntry {
    pub id: &'static str,
    pub display_name: &'static str,
    pub bank_code: &'static str,
    pub kind: StatementKind,
    /// What the claim actually proves. Ranked after `kind`, so a product-level claim beats a
    /// bank-level one for the same institution and kind — and the three doubly-claimed
    /// ledger fixtures are untouched.
    pub evidence: ClaimEvidence,
    /// Receives the document's identity and header regions, never its raw text
    /// (`statement::claim`).
    pub claims: fn(&Regions) -> bool,
    read: fn(&[String], &str, &[LineWords]) -> ParsedStatement,
}

const REGISTRY: &[ReaderEntry] = &[
    ReaderEntry {
        id: "AU_BANK",
        display_name: "AU Small Finance Bank Account",
        bank_code: au_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        evidence: ClaimEvidence::BankLevel,
        claims: au_bank_claims,
        read: read_au_bank,
    },
    ReaderEntry {
        id: "FEDERAL_BANK",
        display_name: "Federal Bank Account",
        bank_code: federal_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        evidence: ClaimEvidence::BankLevel,
        claims: federal_bank_claims,
        read: read_federal_bank,
    },
    ReaderEntry {
        id: "HDFC_BANK",
        display_name: "HDFC Bank Account",
        bank_code: hdfc_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        evidence: ClaimEvidence::BankLevel,
        claims: hdfc_bank_claims,
        read: read_hdfc_bank,
    },
    ReaderEntry {
        id: "ICICI_BANK",
        display_name: "ICICI Bank Account",
        bank_code: icici_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        evidence: ClaimEvidence::BankLevel,
        claims: icici_bank_claims,
        read: read_icici_bank,
    },
    ReaderEntry {
        id: "FEDERAL_SCAPIA_CARD",
        display_name: "Scapia Credit Card",
        bank_code: federal::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::BankLevel,
        claims: federal_card_claims,
        read: read_federal_card,
    },
    ReaderEntry {
        id: "HDFC_SWIGGY_CARD",
        display_name: "HDFC Swiggy Credit Card",
        bank_code: hdfc::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::ProductProven,
        claims: hdfc_card_claims,
        read: read_hdfc_card,
    },
    ReaderEntry {
        id: "ICICI_AMAZONPAY_CARD",
        display_name: "ICICI Amazon Pay Credit Card",
        bank_code: icici::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::BankLevel,
        claims: icici_card_claims,
        read: read_icici_card,
    },
    ReaderEntry {
        id: "IOB_RUPAY_CARD",
        display_name: "IOB RuPay Credit Card",
        bank_code: iob::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::BankLevel,
        claims: iob_card_claims,
        read: read_iob_card,
    },
    ReaderEntry {
        id: "SBI_CASHBACK_CARD",
        display_name: "SBI Cashback Credit Card",
        bank_code: sbi::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::BankLevel,
        claims: sbi_card_claims,
        read: read_sbi_card,
    },
    ReaderEntry {
        id: "YES_KIWI_CARD",
        display_name: "Kiwi (YES Bank) Credit Card",
        bank_code: yes::BANK_CODE,
        kind: StatementKind::CreditCard,
        evidence: ClaimEvidence::BankLevel,
        claims: yes_card_claims,
        read: read_yes_card,
    },
];

pub fn entries() -> &'static [ReaderEntry] {
    REGISTRY
}

/// Specificity: a claim that proves its product outranks one that only names a bank.
pub fn evidence_rank(evidence: ClaimEvidence) -> u8 {
    match evidence {
        ClaimEvidence::ProductProven => 0,
        ClaimEvidence::BankLevel => 1,
    }
}

pub fn kind_rank(kind: StatementKind) -> u8 {
    match kind {
        StatementKind::BankAccount => 0,
        StatementKind::CreditCard => 1,
    }
}

/// Every reader that claims a document, in registry order.
///
/// Exposed because "which readers claimed this?" is a sharper question than "which one
/// won?": a false claim that happens to lose the tie-break is still a false claim, and the
/// gate that fences the AU/HDFC hazard has to be able to see it.
pub fn claimants(full_text: &str) -> Vec<&'static ReaderEntry> {
    let regions = Regions::of(full_text);
    REGISTRY
        .iter()
        .filter(|entry| (entry.claims)(&regions))
        .collect()
}

pub fn detect_issuer(full_text: &str) -> Option<Issuer> {
    claimants(full_text)
        .into_iter()
        .min_by_key(|entry| {
            (
                kind_rank(entry.kind),
                evidence_rank(entry.evidence),
                entry.id,
            )
        })
        .map(to_issuer)
}

pub fn read_statement(
    issuer: &Issuer,
    lines: &[String],
    full_text: &str,
    line_words: &[LineWords],
) -> Result<ParsedStatement, ReaderError> {
    let Some(entry) = REGISTRY.iter().find(|entry| entry.id == issuer.id) else {
        return Err(ReaderError::UnknownIssuer {
            id: issuer.id.clone(),
        });
    };
    Ok((entry.read)(lines, full_text, line_words))
}

fn to_issuer(entry: &ReaderEntry) -> Issuer {
    Issuer {
        id: entry.id.to_string(),
        display_name: entry.display_name.to_string(),
        bank_code: entry.bank_code.to_string(),
        kind: entry.kind,
    }
}

fn au_bank_claims(regions: &Regions) -> bool {
    ledger_reader::claims_ledger(&au_bank::AuBankReader, regions, au_bank::BANK_CODE)
}

fn federal_bank_claims(regions: &Regions) -> bool {
    ledger_reader::claims_ledger(
        &federal_bank::FederalBankReader,
        regions,
        federal_bank::BANK_CODE,
    )
}

fn hdfc_bank_claims(regions: &Regions) -> bool {
    ledger_reader::claims_ledger(&hdfc_bank::HdfcBankReader, regions, hdfc_bank::BANK_CODE)
}

fn icici_bank_claims(regions: &Regions) -> bool {
    ledger_reader::claims_ledger(&icici_bank::IciciBankReader, regions, icici_bank::BANK_CODE)
}

fn federal_card_claims(regions: &Regions) -> bool {
    line_reader::claims(&federal::FederalReader, regions, federal::BANK_CODE)
}

fn hdfc_card_claims(regions: &Regions) -> bool {
    hdfc::hdfc_claims(regions)
}

fn icici_card_claims(regions: &Regions) -> bool {
    line_reader::claims(&icici::IciciReader, regions, icici::BANK_CODE)
}

fn iob_card_claims(regions: &Regions) -> bool {
    line_reader::claims(&iob::IobReader, regions, iob::BANK_CODE)
}

fn sbi_card_claims(regions: &Regions) -> bool {
    line_reader::claims(&sbi::SbiReader, regions, sbi::BANK_CODE)
}

fn yes_card_claims(regions: &Regions) -> bool {
    line_reader::claims(&yes::YesReader, regions, yes::BANK_CODE)
}

fn read_au_bank(lines: &[String], full_text: &str, line_words: &[LineWords]) -> ParsedStatement {
    read_ledger(&au_bank::AuBankReader, lines, full_text, line_words)
}

fn read_federal_bank(
    lines: &[String],
    full_text: &str,
    line_words: &[LineWords],
) -> ParsedStatement {
    read_ledger(
        &federal_bank::FederalBankReader,
        lines,
        full_text,
        line_words,
    )
}

fn read_hdfc_bank(lines: &[String], full_text: &str, line_words: &[LineWords]) -> ParsedStatement {
    read_ledger(&hdfc_bank::HdfcBankReader, lines, full_text, line_words)
}

fn read_icici_bank(lines: &[String], full_text: &str, line_words: &[LineWords]) -> ParsedStatement {
    read_ledger(&icici_bank::IciciBankReader, lines, full_text, line_words)
}

fn read_federal_card(
    lines: &[String],
    full_text: &str,
    _line_words: &[LineWords],
) -> ParsedStatement {
    line_reader::read_lines(&federal::FederalReader, lines, full_text)
}

fn read_hdfc_card(lines: &[String], full_text: &str, _line_words: &[LineWords]) -> ParsedStatement {
    hdfc::read_hdfc_statement(lines, full_text)
}

fn read_icici_card(
    lines: &[String],
    full_text: &str,
    _line_words: &[LineWords],
) -> ParsedStatement {
    line_reader::read_lines(&icici::IciciReader, lines, full_text)
}

fn read_iob_card(lines: &[String], full_text: &str, _line_words: &[LineWords]) -> ParsedStatement {
    line_reader::read_lines(&iob::IobReader, lines, full_text)
}

fn read_sbi_card(lines: &[String], full_text: &str, _line_words: &[LineWords]) -> ParsedStatement {
    line_reader::read_lines(&sbi::SbiReader, lines, full_text)
}

fn read_yes_card(lines: &[String], full_text: &str, _line_words: &[LineWords]) -> ParsedStatement {
    line_reader::read_lines(&yes::YesReader, lines, full_text)
}

fn read_ledger<C: ledger_reader::LedgerReaderConfig + ?Sized>(
    cfg: &C,
    lines: &[String],
    full_text: &str,
    line_words: &[LineWords],
) -> ParsedStatement {
    let words = ledger_reader::first_anchor_index(cfg, lines)
        .and_then(|index| {
            line_words
                .iter()
                .find(|line| line.line_index as usize == index)
        })
        .map(|line| line.words.clone())
        .unwrap_or_default();
    ledger_reader::read_ledger_lines(cfg, lines, full_text, &words)
}
