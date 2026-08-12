use crate::ffi::{Issuer, ReaderError, StatementKind};
use crate::statement::base::{LineWords, ParsedStatement};
use crate::statement::{au_bank, federal, federal_bank, hdfc, hdfc_bank, icici, icici_bank, iob};
use crate::statement::{ledger_reader, line_reader, sbi, yes};

/// One reader registered with the dispatcher.
#[derive(Debug)]
pub struct ReaderEntry {
    pub id: &'static str,
    pub display_name: &'static str,
    pub bank_code: &'static str,
    pub kind: StatementKind,
    pub claims: fn(&str) -> bool,
    read: fn(&[String], &str, &[LineWords]) -> ParsedStatement,
}

const REGISTRY: &[ReaderEntry] = &[
    ReaderEntry {
        id: "AU_BANK",
        display_name: "AU Small Finance Bank Account",
        bank_code: au_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        claims: au_bank_claims,
        read: read_au_bank,
    },
    ReaderEntry {
        id: "FEDERAL_BANK",
        display_name: "Federal Bank Account",
        bank_code: federal_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        claims: federal_bank_claims,
        read: read_federal_bank,
    },
    ReaderEntry {
        id: "HDFC_BANK",
        display_name: "HDFC Bank Account",
        bank_code: hdfc_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        claims: hdfc_bank_claims,
        read: read_hdfc_bank,
    },
    ReaderEntry {
        id: "ICICI_BANK",
        display_name: "ICICI Bank Account",
        bank_code: icici_bank::BANK_CODE,
        kind: StatementKind::BankAccount,
        claims: icici_bank_claims,
        read: read_icici_bank,
    },
    ReaderEntry {
        id: "FEDERAL_CARD",
        display_name: "Scapia Credit Card",
        bank_code: federal::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: federal_card_claims,
        read: read_federal_card,
    },
    ReaderEntry {
        id: "HDFC_CARD",
        display_name: "HDFC Bank Credit Card",
        bank_code: hdfc::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: hdfc_card_claims,
        read: read_hdfc_card,
    },
    ReaderEntry {
        id: "ICICI_CARD",
        display_name: "ICICI Bank Credit Card",
        bank_code: icici::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: icici_card_claims,
        read: read_icici_card,
    },
    ReaderEntry {
        id: "IOB_CARD",
        display_name: "Indian Overseas Bank Credit Card",
        bank_code: iob::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: iob_card_claims,
        read: read_iob_card,
    },
    ReaderEntry {
        id: "SBI_CARD",
        display_name: "SBI Card",
        bank_code: sbi::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: sbi_card_claims,
        read: read_sbi_card,
    },
    ReaderEntry {
        id: "YES_CARD",
        display_name: "Kiwi (YES Bank) Credit Card",
        bank_code: yes::BANK_CODE,
        kind: StatementKind::CreditCard,
        claims: yes_card_claims,
        read: read_yes_card,
    },
];

pub fn entries() -> &'static [ReaderEntry] {
    REGISTRY
}

pub fn kind_rank(kind: StatementKind) -> u8 {
    match kind {
        StatementKind::BankAccount => 0,
        StatementKind::CreditCard => 1,
    }
}

pub fn detect_issuer(full_text: &str) -> Option<Issuer> {
    REGISTRY
        .iter()
        .filter(|entry| (entry.claims)(full_text))
        .min_by_key(|entry| (kind_rank(entry.kind), entry.id))
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

fn au_bank_claims(full_text: &str) -> bool {
    ledger_reader::claims_ledger(&au_bank::AuBankReader, full_text, au_bank::BANK_CODE)
}

fn federal_bank_claims(full_text: &str) -> bool {
    ledger_reader::claims_ledger(
        &federal_bank::FederalBankReader,
        full_text,
        federal_bank::BANK_CODE,
    )
}

fn hdfc_bank_claims(full_text: &str) -> bool {
    ledger_reader::claims_ledger(&hdfc_bank::HdfcBankReader, full_text, hdfc_bank::BANK_CODE)
}

fn icici_bank_claims(full_text: &str) -> bool {
    ledger_reader::claims_ledger(
        &icici_bank::IciciBankReader,
        full_text,
        icici_bank::BANK_CODE,
    )
}

fn federal_card_claims(full_text: &str) -> bool {
    line_reader::claims(&federal::FederalReader, full_text, federal::BANK_CODE)
}

fn hdfc_card_claims(full_text: &str) -> bool {
    hdfc::hdfc_claims(full_text)
}

fn icici_card_claims(full_text: &str) -> bool {
    line_reader::claims(&icici::IciciReader, full_text, icici::BANK_CODE)
}

fn iob_card_claims(full_text: &str) -> bool {
    line_reader::claims(&iob::IobReader, full_text, iob::BANK_CODE)
}

fn sbi_card_claims(full_text: &str) -> bool {
    line_reader::claims(&sbi::SbiReader, full_text, sbi::BANK_CODE)
}

fn yes_card_claims(full_text: &str) -> bool {
    line_reader::claims(&yes::YesReader, full_text, yes::BANK_CODE)
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
