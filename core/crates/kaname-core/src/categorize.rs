//! Deterministic, on-device transaction categorization — the pure port of the web
//! engine's first-wins categorization stack (CC rules → T1 source-category map → T2
//! merchant map → T3 rules). The LLM stage (T4) is a Pro/server concern (ADR-0003) and
//! is intentionally absent here.
//!
//! The `categorize` entry point assigns each transaction exactly one [`Category`] — named
//! by a stable [`CategoryRef`] — and reports which [`Stage`] fired, or returns `None` when
//! nothing matches (*uncategorized*) rather than guessing. It is pure, deterministic and
//! read-only: it reads only the passed-in facts (the catalog, merchant map, rules and
//! source-category map) and never touches storage, the clock, the network or a locale.
//! The encrypted store (P2+) loads those facts and persists the result; the engine owns
//! only the decision.
//!
//! Reuses, rather than re-ports, the already-ported [`crate::dedup::normalize_narration`]
//! (the exact key the merchant map is scanned against, identical to de-dup), the matcher
//! semantics (`KEYWORD` = case-insensitive substring, `REGEX`, `AMOUNT_RANGE`) and the
//! statement's own [`Direction`] (from `polarity::classify`, never the amount's sign).
//!
//! # Precedence
//! First-wins across the stages in the fixed order above. Within T3, lower `priority`
//! wins and, at equal priority, user rules are applied before system rules.

use std::str::FromStr;
use std::sync::LazyLock;

use regex::{Regex, RegexBuilder};
use rust_decimal::Decimal;

use crate::dedup::normalize_narration;
use crate::model::Direction;

/// The rename-proof money-bucket a [`Category`] rolls up to for analytics. Distinct from
/// the category's display name; `None` means "fall back to the transaction [`Direction`]".
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Classification {
    /// Ordinary spending (the default bucket for expenses).
    Spend,
    /// Money earned — salary, freelance and other income.
    Income,
    /// Money moved into investments (SIPs, mutual funds, stocks, FDs).
    Investment,
    /// Money moved between the user's own accounts — excluded from spend.
    Transfer,
    /// A credit-card bill paid from a bank account — excluded from spend.
    CcPayment,
    /// Cashbacks, rewards, refunds and reimbursements — reduce spend.
    Refund,
}

/// A stable, database-free reference to the category a [`Decision`] assigned.
///
/// [`CategoryRef::Builtin`] carries the stable code of one of the 23 ported defaults (see
/// [`default_categories`]); [`CategoryRef::Custom`] echoes the caller-supplied opaque id of
/// a user category already present in the passed-in facts. The store resolves either to
/// its own row, so the pure core needs no database.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum CategoryRef {
    /// One of the 23 built-in defaults, named by its stable code (e.g. `GROCERIES`).
    Builtin { code: String },
    /// A user category, named by the caller-supplied opaque id.
    Custom { id: String },
}

/// One entry in the category catalog: its [`CategoryRef`], display `name`, and money-bucket
/// [`Classification`] (`None` ⇒ fall back to the transaction direction). The core carries
/// name + classification only; colour / emoji / description remain platform-side concerns.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Category {
    pub category_ref: CategoryRef,
    pub name: String,
    pub classification: Option<Classification>,
}

/// How a [`MerchantRule`] (T2, the "memory") is matched against the normalized narration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MerchantMatch {
    /// Case-insensitive substring of the normalized narration.
    Literal,
    /// A regular expression searched against the normalized narration.
    Regex,
}

/// One merchant-map entry (T2): a normalized-narration `pattern` that, when it matches,
/// assigns `category`. Lower `priority` is tried first.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MerchantRule {
    pub priority: i64,
    pub match_type: MerchantMatch,
    pub pattern: String,
    pub category: CategoryRef,
}

/// How a [`Rule`] (T3) is matched.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum RuleMatch {
    /// Case-insensitive substring of the raw narration.
    Keyword,
    /// A regular expression searched (case-insensitively) against the raw narration.
    Regex,
    /// The transaction's absolute amount falls within an inclusive `"lo,hi"` range.
    AmountRange,
}

/// One T3 rule. `value` is the keyword, the regex pattern, or the `"lo,hi"` amount range,
/// per `match_type`. Resolution is by `priority` (lower wins); at equal priority a user
/// rule (`is_system == false`) is applied before a system rule. `id`, when present, is
/// echoed into the [`Decision`] as `matched_rule_id`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Rule {
    pub id: Option<String>,
    pub priority: i64,
    pub is_system: bool,
    pub match_type: RuleMatch,
    pub value: String,
    pub category: CategoryRef,
}

/// One source-category-map entry (T1): the issuer's own category hint
/// `(bank_code, source_category)` mapped to a Kaname `category` by exact lookup.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SourceCategoryMapping {
    pub bank_code: String,
    pub source_category: String,
    pub category: CategoryRef,
}

/// The transaction being categorized, reduced to the facts the stack reads. `direction`
/// is the statement's own Dr/Cr (from `polarity::classify`) — never inferred from the
/// amount's sign — and `is_credit_card` marks a credit-card account (the CC-rule gate).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CategoryTxn {
    pub bank_code: String,
    pub is_credit_card: bool,
    pub source_category: Option<String>,
    pub description: String,
    pub amount: Decimal,
    pub direction: Direction,
}

/// Which stage of the stack assigned the category — the audit trail of a [`Decision`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Stage {
    /// The India-specific credit-card narration rules (stage 0).
    CcRule,
    /// T1 — the issuer's source-category map.
    T1SourceCategory,
    /// T2 — the user merchant map (the "memory").
    T2MerchantMap,
    /// T3 — the keyword / regex / amount-range rules.
    T3Rule,
}

/// The outcome of a successful categorization: the assigned `category_ref`, the `stage`
/// that fired, and (for T3 only) the `matched_rule_id`. There is deliberately **no**
/// confidence field — only the excluded LLM stage carried one. *Uncategorized* is
/// represented by `categorize` returning `None`, not by a variant here.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Decision {
    pub category_ref: CategoryRef,
    pub stage: Stage,
    pub matched_rule_id: Option<String>,
}

/// The 23 ported defaults as `(code, name, classification)`. The single source of truth
/// for [`default_categories`] and built-in name resolution. Tally: 16 SPEND, 2 INCOME,
/// 1 INVESTMENT, 1 TRANSFER, 1 CC_PAYMENT, 2 REFUND (mirrors the web `DEFAULT_CATEGORIES`).
const BUILTIN_CATEGORIES: &[(&str, &str, Classification)] = &[
    ("FOOD_AND_DINING", "Food & Dining", Classification::Spend),
    ("GROCERIES", "Groceries", Classification::Spend),
    ("TRANSPORT", "Transport", Classification::Spend),
    ("FUEL", "Fuel", Classification::Spend),
    ("SHOPPING", "Shopping", Classification::Spend),
    ("ENTERTAINMENT", "Entertainment", Classification::Spend),
    ("SUBSCRIPTIONS", "Subscriptions", Classification::Spend),
    (
        "HEALTH_AND_MEDICAL",
        "Health & Medical",
        Classification::Spend,
    ),
    ("EDUCATION", "Education", Classification::Spend),
    ("UTILITIES", "Utilities", Classification::Spend),
    ("RENT_EMI", "Rent / EMI", Classification::Spend),
    ("INSURANCE", "Insurance", Classification::Spend),
    ("INVESTMENTS", "Investments", Classification::Investment),
    ("SELF_TRANSFER", "Self Transfer", Classification::Transfer),
    (
        "CREDIT_CARD_BILL_PAYMENT",
        "Credit Card Bill Payment",
        Classification::CcPayment,
    ),
    ("TRAVEL", "Travel", Classification::Spend),
    (
        "GIFTS_AND_DONATIONS",
        "Gifts & Donations",
        Classification::Spend,
    ),
    ("SALARY_INCOME", "Salary / Income", Classification::Income),
    (
        "FREELANCE_INCOME",
        "Freelance Income",
        Classification::Income,
    ),
    (
        "CASHBACKS_AND_REFUNDS",
        "Cashbacks & Refunds",
        Classification::Refund,
    ),
    ("REIMBURSEMENT", "Reimbursement", Classification::Refund),
    ("SETTLE_UP", "Settle Up", Classification::Spend),
    ("MISCELLANEOUS", "Miscellaneous", Classification::Spend),
];

/// The 23 built-in default categories (name + [`Classification`] only) as a catalog the
/// caller can seed from and extend with the user's own categories. Ported verbatim from
/// the web engine's `DEFAULT_CATEGORIES`; display metadata (colour / emoji / description)
/// stays platform-side. Surfaced over UniFFI by [`crate::default_categories`].
pub fn default_categories() -> Vec<Category> {
    BUILTIN_CATEGORIES
        .iter()
        .map(|&(code, name, classification)| Category {
            category_ref: CategoryRef::Builtin {
                code: code.to_string(),
            },
            name: name.to_string(),
            classification: Some(classification),
        })
        .collect()
}

/// The two built-in categories the India-specific credit-card rules can assign. Modelling
/// the outcome as a type (rather than a display-name string re-resolved later) keeps the
/// name↔code mapping in one place and makes the resolution total.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CcCategory {
    /// A credit-card bill payment (either CC rule).
    BillPayment,
    /// A credit-card cashback / refund inflow.
    CashbackRefund,
}

impl CcCategory {
    /// The stable built-in code (the `CategoryRef::Builtin` identity).
    fn code(self) -> &'static str {
        match self {
            CcCategory::BillPayment => "CREDIT_CARD_BILL_PAYMENT",
            CcCategory::CashbackRefund => "CASHBACKS_AND_REFUNDS",
        }
    }

    /// The display name, matched against a caller catalog entry (a re-slugged default).
    fn name(self) -> &'static str {
        match self {
            CcCategory::BillPayment => "Credit Card Bill Payment",
            CcCategory::CashbackRefund => "Cashbacks & Refunds",
        }
    }
}

/// A reward/cashback card line commonly leads with a percentage, e.g. `10% Swiggy Cashback`.
static LEADING_PERCENT: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*\d+(?:\.\d+)?\s*%").expect("valid literal regex"));

/// Cashback / refund language on a card inflow (checked before bill-payment language).
const CASHBACK_REFUND_KEYWORDS: &[&str] = &[
    "cashback",
    "cash back",
    "cback",
    "reward",
    "refund",
    "reversal",
    "reversed",
    "credit adjustment",
];

/// Bill-payment language on a card inflow.
const BILL_PAYMENT_KEYWORDS: &[&str] = &[
    "payment received",
    "pymt recd",
    "pymnt recd",
    "pymt received",
    "payment recd",
    "payment recvd",
    "recd - thank you",
    "recd thank you",
    "received, thank you",
    "received thank you",
    "thank you",
    "autopay received",
    "auto pay received",
    "billpayment",
    "bill payment",
    "bbps",
    "e-payment",
    "epayment",
];

/// Classify a credit-card **inflow** narration — the verbatim port of the web
/// `cc_credit_rule.classify_cc_credit`. Cashback / refund language (including a leading
/// percentage) wins over bill-payment language, so a "Cashback … thank you" line is a
/// refund, not a payment. `None` defers to the tiers.
fn classify_cc_credit(narration: &str) -> Option<CcCategory> {
    let haystack = narration.to_lowercase();
    if haystack.trim().is_empty() {
        return None;
    }
    if LEADING_PERCENT.is_match(&haystack)
        || CASHBACK_REFUND_KEYWORDS
            .iter()
            .any(|k| haystack.contains(k))
    {
        return Some(CcCategory::CashbackRefund);
    }
    if BILL_PAYMENT_KEYWORDS.iter().any(|k| haystack.contains(k)) {
        return Some(CcCategory::BillPayment);
    }
    None
}

/// A card *token* — a whole word, so a bare merchant like `BIGCARD STORE` does not match.
static CARD_TOKEN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\b(?:CREDIT\s+CARD|CC|CARD)\b").expect("valid card regex"));
/// A payment-intent token (`PAYMENT`/`AUTOPAY`/`AUTO PAY`/`BBPS`/`BPAY`/`PMT`).
static PAYMENT_INTENT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:PAYMENTS?|AUTOPAY|AUTO\s+PAY|BBPS|BPAY|PMT)\b")
        .expect("valid intent regex")
});
/// Hard exclusions — a card **fee** or an **EMI** is a charge, never a bill payment.
static CC_DEBIT_EXCLUSION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\b(?:EMI|FEES?)\b").expect("valid exclusion regex"));

/// Classify a bank-side (non-card) **outflow** narration — the verbatim port of the web
/// `cc_debit_rule.classify_cc_debit`. Fires only when a payment-intent token co-occurs
/// with a card token and the line is not a card fee or an EMI (the exclusion wins).
fn classify_cc_debit(narration: &str) -> Option<CcCategory> {
    if narration.trim().is_empty() {
        return None;
    }
    if CC_DEBIT_EXCLUSION.is_match(narration) {
        return None;
    }
    if PAYMENT_INTENT.is_match(narration) && CARD_TOKEN.is_match(narration) {
        return Some(CcCategory::BillPayment);
    }
    None
}

/// Resolve a CC-rule outcome to a built-in [`CategoryRef`]. It honours a caller catalog
/// entry that is *itself* a built-in of that name (a re-slugged default), never a user's
/// custom category that merely shares the name; otherwise it falls back to the stable
/// code. Always a [`CategoryRef::Builtin`] — the two CC categories are ported defaults.
fn cc_category_ref(catalog: &[Category], cc: CcCategory) -> CategoryRef {
    catalog
        .iter()
        .find(|c| {
            c.name.eq_ignore_ascii_case(cc.name())
                && matches!(c.category_ref, CategoryRef::Builtin { .. })
        })
        .map(|c| c.category_ref.clone())
        .unwrap_or_else(|| CategoryRef::Builtin {
            code: cc.code().to_string(),
        })
}

/// A compiled T2 merchant matcher — the regex is compiled once by [`prepare_merchants`],
/// so the per-transaction hot path never re-compiles. `Invalid` marks a pattern that would
/// not compile; it simply never matches (mirroring the web engine skipping a bad alias).
enum MerchantMatcher {
    Literal(String),
    Regex(Regex),
    Invalid,
}

/// A T2 merchant-map entry with its matcher already compiled. Built by [`prepare_merchants`].
pub(crate) struct PreparedMerchant {
    matcher: MerchantMatcher,
    category: CategoryRef,
}

/// A compiled T3 rule matcher — regex and amount-range are parsed/compiled once by
/// [`prepare_rules`]. `Invalid` marks a bad regex or malformed range that never matches.
enum RuleMatcher {
    Keyword(String),
    Regex(Regex),
    AmountRange(Decimal, Decimal),
    Invalid,
}

/// A T3 rule with its matcher already compiled. Built by [`prepare_rules`].
pub(crate) struct PreparedRule {
    id: Option<String>,
    matcher: RuleMatcher,
    category: CategoryRef,
}

/// Compile the merchant map once — the "precompiled regex" the design requires — so the
/// same prepared facts can be reused across every transaction in a batch. Entries are
/// returned in evaluation order (ascending `priority`, the caller's input order breaking
/// ties via the stable sort). Patterns are lower-cased before compiling, exactly as the web
/// `merchant_identity._match_global_merchant` does (`alias_pattern.lower()`), so matching
/// against the already-lower-cased normalized narration reproduces the web byte-for-byte.
pub(crate) fn prepare_merchants(merchants: &[MerchantRule]) -> Vec<PreparedMerchant> {
    let mut prepared: Vec<(i64, PreparedMerchant)> = merchants
        .iter()
        .map(|m| {
            let lowered = m.pattern.to_lowercase();
            let matcher = match m.match_type {
                MerchantMatch::Literal => MerchantMatcher::Literal(lowered),
                MerchantMatch::Regex => match Regex::new(&lowered) {
                    Ok(re) => MerchantMatcher::Regex(re),
                    Err(_) => MerchantMatcher::Invalid,
                },
            };
            (
                m.priority,
                PreparedMerchant {
                    matcher,
                    category: m.category.clone(),
                },
            )
        })
        .collect();
    prepared.sort_by_key(|(priority, _)| *priority);
    prepared.into_iter().map(|(_, m)| m).collect()
}

/// Compile the T3 rules once, returned in evaluation order — ascending `priority`, then
/// user rules before system rules (`false < true`) at equal priority, the caller's input
/// order breaking any remaining tie via the stable sort. Keyword text is lower-cased,
/// regexes are built case-insensitively, and each `"lo,hi"` amount range is parsed to a
/// [`Decimal`] pair.
pub(crate) fn prepare_rules(rules: &[Rule]) -> Vec<PreparedRule> {
    let mut prepared: Vec<(i64, bool, PreparedRule)> = rules
        .iter()
        .map(|r| {
            let matcher = match r.match_type {
                RuleMatch::Keyword => RuleMatcher::Keyword(r.value.to_lowercase()),
                RuleMatch::Regex => RegexBuilder::new(&r.value)
                    .case_insensitive(true)
                    .build()
                    .map(RuleMatcher::Regex)
                    .unwrap_or(RuleMatcher::Invalid),
                RuleMatch::AmountRange => match parse_amount_range(&r.value) {
                    Some((lo, hi)) => RuleMatcher::AmountRange(lo, hi),
                    None => RuleMatcher::Invalid,
                },
            };
            (
                r.priority,
                r.is_system,
                PreparedRule {
                    id: r.id.clone(),
                    matcher,
                    category: r.category.clone(),
                },
            )
        })
        .collect();
    prepared.sort_by_key(|(priority, is_system, _)| (*priority, *is_system));
    prepared.into_iter().map(|(_, _, r)| r).collect()
}

/// Parse a `"lo,hi"` amount range to a [`Decimal`] pair, or `None` on any parse failure —
/// exactly the web `_matches` AMOUNT_RANGE contract (a malformed range never matches).
fn parse_amount_range(spec: &str) -> Option<(Decimal, Decimal)> {
    let (lo, hi) = spec.split_once(',')?;
    Some((
        Decimal::from_str(lo.trim()).ok()?,
        Decimal::from_str(hi.trim()).ok()?,
    ))
}

/// Categorize one transaction with the deterministic first-wins stack — the pure engine
/// hot path over already-[`prepare_merchants`]d / [`prepare_rules`]d facts (compiled and
/// priority-ordered once, then reused per transaction). Returns the [`Decision`] of the
/// first stage to fire (**CC rules → T1 → T2 → T3**), or `None` when nothing matches.
/// Callers cross the UniFFI boundary via the exported `categorize` / `categorize_batch`
/// (in `ffi.rs`), which prepare the facts then delegate here.
///
/// - **Stage 0 (CC rules):** for a credit-card inflow, `classify_cc_credit`; for a
///   non-card outflow, `classify_cc_debit`. A hit resolves to its built-in category.
/// - **T1:** exact `(bank_code, source_category)` lookup in `source_map`.
/// - **T2:** the merchant map, scanned against the reused [`normalize_narration`] —
///   literal substring or precompiled regex; first match wins.
/// - **T3:** the rules — keyword / regex on the raw narration, or an amount range.
pub(crate) fn categorize(
    txn: &CategoryTxn,
    catalog: &[Category],
    merchants: &[PreparedMerchant],
    rules: &[PreparedRule],
    source_map: &[SourceCategoryMapping],
) -> Option<Decision> {
    // The two CC gates are mutually exclusive: a card inflow, or a bank-side (non-card) outflow.
    let cc = if txn.is_credit_card && txn.direction == Direction::Credit {
        classify_cc_credit(&txn.description)
    } else if !txn.is_credit_card && txn.direction == Direction::Debit {
        classify_cc_debit(&txn.description)
    } else {
        None
    };
    if let Some(cc) = cc {
        return Some(Decision {
            category_ref: cc_category_ref(catalog, cc),
            stage: Stage::CcRule,
            matched_rule_id: None,
        });
    }

    if let Some(source_category) = txn.source_category.as_deref() {
        if let Some(mapping) = source_map
            .iter()
            .find(|m| m.bank_code == txn.bank_code && m.source_category == source_category)
        {
            return Some(Decision {
                category_ref: mapping.category.clone(),
                stage: Stage::T1SourceCategory,
                matched_rule_id: None,
            });
        }
    }

    let normalized = normalize_narration(&txn.description);
    for merchant in merchants {
        let matched = match &merchant.matcher {
            MerchantMatcher::Literal(pattern) => normalized.contains(pattern.as_str()),
            MerchantMatcher::Regex(re) => re.is_match(&normalized),
            MerchantMatcher::Invalid => false,
        };
        if matched {
            return Some(Decision {
                category_ref: merchant.category.clone(),
                stage: Stage::T2MerchantMap,
                matched_rule_id: None,
            });
        }
    }

    for rule in rules {
        if rule_matches(&rule.matcher, txn) {
            return Some(Decision {
                category_ref: rule.category.clone(),
                stage: Stage::T3Rule,
                matched_rule_id: rule.id.clone(),
            });
        }
    }

    None
}

/// Whether a compiled T3 `matcher` matches `txn` — keyword (case-insensitive substring) or
/// regex (case-insensitive) on the raw narration, or the absolute amount inside an
/// inclusive range. An `Invalid` matcher never matches (mirrors the web engine).
fn rule_matches(matcher: &RuleMatcher, txn: &CategoryTxn) -> bool {
    match matcher {
        RuleMatcher::Keyword(keyword) => txn.description.to_lowercase().contains(keyword.as_str()),
        RuleMatcher::Regex(re) => re.is_match(&txn.description),
        RuleMatcher::AmountRange(lo, hi) => {
            let amount = txn.amount.abs();
            *lo <= amount && amount <= *hi
        }
        RuleMatcher::Invalid => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn txn(is_cc: bool, direction: Direction, description: &str) -> CategoryTxn {
        CategoryTxn {
            bank_code: "ICICI".to_string(),
            is_credit_card: is_cc,
            source_category: None,
            description: description.to_string(),
            amount: dec!(100.00),
            direction,
        }
    }

    fn builtin(code: &str) -> CategoryRef {
        CategoryRef::Builtin {
            code: code.to_string(),
        }
    }

    /// Categorize via the raw (spec) facts — prepares once, then runs the hot path, exactly
    /// as the FFI boundary does — so the tests exercise `prepare_*` + `categorize` together.
    fn run(
        txn: &CategoryTxn,
        catalog: &[Category],
        merchants: &[MerchantRule],
        rules: &[Rule],
        source_map: &[SourceCategoryMapping],
    ) -> Option<Decision> {
        categorize(
            txn,
            catalog,
            &prepare_merchants(merchants),
            &prepare_rules(rules),
            source_map,
        )
    }

    #[test]
    fn ports_the_twenty_three_defaults_with_classifications() {
        let cats = default_categories();
        assert_eq!(cats.len(), 23);
        let count = |c: Classification| cats.iter().filter(|x| x.classification == Some(c)).count();
        assert_eq!(count(Classification::Spend), 16);
        assert_eq!(count(Classification::Income), 2);
        assert_eq!(count(Classification::Investment), 1);
        assert_eq!(count(Classification::Transfer), 1);
        assert_eq!(count(Classification::CcPayment), 1);
        assert_eq!(count(Classification::Refund), 2);
        // Every default is a built-in and every classification is present.
        assert!(cats
            .iter()
            .all(|c| matches!(c.category_ref, CategoryRef::Builtin { .. })
                && c.classification.is_some()));
    }

    #[test]
    fn cc_credit_only_fires_for_card_inflows() {
        let catalog = default_categories();
        // A card inflow with bill-payment language → CC rule, built-in bill payment.
        let d = run(
            &txn(
                true,
                Direction::Credit,
                "ONLINE TRF - PYMT RECD - THANK YOU",
            ),
            &catalog,
            &[],
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(d.stage, Stage::CcRule);
        assert_eq!(d.category_ref, builtin("CREDIT_CARD_BILL_PAYMENT"));
        assert!(d.matched_rule_id.is_none());
        // The same narration as a card *debit* is not a CC-credit hit.
        assert!(run(
            &txn(true, Direction::Debit, "ONLINE TRF - PYMT RECD - THANK YOU"),
            &catalog,
            &[],
            &[],
            &[],
        )
        .is_none());
    }

    #[test]
    fn cc_credit_cashback_wins_over_payment_language() {
        let catalog = default_categories();
        let d = run(
            &txn(true, Direction::Credit, "Cashback received, thank you"),
            &catalog,
            &[],
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(d.category_ref, builtin("CASHBACKS_AND_REFUNDS"));
    }

    #[test]
    fn cc_debit_requires_card_and_intent_and_excludes_fees_and_emi() {
        let catalog = default_categories();
        let hit = run(
            &txn(false, Direction::Debit, "ICICI CREDIT CARD PAYMENT"),
            &catalog,
            &[],
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(hit.stage, Stage::CcRule);
        assert_eq!(hit.category_ref, builtin("CREDIT_CARD_BILL_PAYMENT"));
        // Card token but no payment intent; payment intent but no card token; EMI exclusion.
        for narration in [
            "GIFT CARD PURCHASE",
            "PAYMENT TO JOHN DOE",
            "CC EMI PAYMENT",
        ] {
            assert!(
                run(
                    &txn(false, Direction::Debit, narration),
                    &catalog,
                    &[],
                    &[],
                    &[],
                )
                .is_none(),
                "{narration} must not be a bank-side CC payment"
            );
        }
    }

    #[test]
    fn first_wins_order_is_cc_then_t1_then_t2_then_t3() {
        let catalog = default_categories();
        let merchants = vec![MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Literal,
            pattern: "acme".to_string(),
            category: builtin("SHOPPING"),
        }];
        let rules = vec![Rule {
            id: Some("r1".to_string()),
            priority: 100,
            is_system: false,
            match_type: RuleMatch::Keyword,
            value: "acme".to_string(),
            category: builtin("MISCELLANEOUS"),
        }];
        let source_map = vec![SourceCategoryMapping {
            bank_code: "ICICI".to_string(),
            source_category: "Food".to_string(),
            category: builtin("FOOD_AND_DINING"),
        }];

        // A bank-side CC payment that would also match T1/T2/T3 still fires the CC rule.
        let mut t = txn(false, Direction::Debit, "ACME CREDIT CARD PAYMENT");
        t.source_category = Some("Food".to_string());
        let d = run(&t, &catalog, &merchants, &rules, &source_map).unwrap();
        assert_eq!(d.stage, Stage::CcRule);

        // Not a CC line → T1 wins over T2 and T3.
        let mut t = txn(false, Direction::Debit, "ACME STORE PURCHASE");
        t.source_category = Some("Food".to_string());
        let d = run(&t, &catalog, &merchants, &rules, &source_map).unwrap();
        assert_eq!(d.stage, Stage::T1SourceCategory);
        assert_eq!(d.category_ref, builtin("FOOD_AND_DINING"));

        // No source hint → T2 (merchant map) wins over T3.
        let t = txn(false, Direction::Debit, "ACME STORE PURCHASE");
        let d = run(&t, &catalog, &merchants, &rules, &source_map).unwrap();
        assert_eq!(d.stage, Stage::T2MerchantMap);
        assert_eq!(d.category_ref, builtin("SHOPPING"));

        // No merchant hit → T3 fires and echoes the rule id.
        let t = txn(false, Direction::Debit, "PAY ACME");
        let no_merchant: Vec<MerchantRule> = vec![];
        let d = run(&t, &catalog, &no_merchant, &rules, &source_map).unwrap();
        assert_eq!(d.stage, Stage::T3Rule);
        assert_eq!(d.matched_rule_id.as_deref(), Some("r1"));
    }

    #[test]
    fn t3_lower_priority_and_user_before_system_wins() {
        let catalog = default_categories();
        let t = txn(false, Direction::Debit, "TEST PAYMENT");
        // Priority 50 must win over 200 regardless of input order.
        let rules = vec![
            Rule {
                id: Some("high".to_string()),
                priority: 200,
                is_system: false,
                match_type: RuleMatch::Keyword,
                value: "test".to_string(),
                category: builtin("SHOPPING"),
            },
            Rule {
                id: Some("low".to_string()),
                priority: 50,
                is_system: false,
                match_type: RuleMatch::Keyword,
                value: "test".to_string(),
                category: builtin("GROCERIES"),
            },
        ];
        let d = run(&t, &catalog, &[], &rules, &[]).unwrap();
        assert_eq!(d.matched_rule_id.as_deref(), Some("low"));

        // At equal priority, the user rule (is_system == false) is applied first.
        let rules = vec![
            Rule {
                id: Some("system".to_string()),
                priority: 1000,
                is_system: true,
                match_type: RuleMatch::Keyword,
                value: "test".to_string(),
                category: builtin("SHOPPING"),
            },
            Rule {
                id: Some("user".to_string()),
                priority: 1000,
                is_system: false,
                match_type: RuleMatch::Keyword,
                value: "test".to_string(),
                category: builtin("GROCERIES"),
            },
        ];
        let d = run(&t, &catalog, &[], &rules, &[]).unwrap();
        assert_eq!(d.matched_rule_id.as_deref(), Some("user"));
    }

    #[test]
    fn t3_regex_and_amount_range_match() {
        let catalog = default_categories();
        let rules = vec![
            Rule {
                id: Some("re".to_string()),
                priority: 10,
                is_system: true,
                match_type: RuleMatch::Regex,
                value: r"\bnetflix\b".to_string(),
                category: builtin("ENTERTAINMENT"),
            },
            Rule {
                id: Some("amt".to_string()),
                priority: 20,
                is_system: true,
                match_type: RuleMatch::AmountRange,
                value: "40000,60000".to_string(),
                category: builtin("RENT_EMI"),
            },
        ];
        let d = run(
            &txn(false, Direction::Debit, "NETFLIX SUBSCRIPTION"),
            &catalog,
            &[],
            &rules,
            &[],
        )
        .unwrap();
        assert_eq!(d.category_ref, builtin("ENTERTAINMENT"));

        let mut t = txn(false, Direction::Debit, "HOUSE RENT");
        t.amount = dec!(50000.00);
        let d = run(&t, &catalog, &[], &rules, &[]).unwrap();
        assert_eq!(d.category_ref, builtin("RENT_EMI"));
    }

    #[test]
    fn t2_uses_the_normalized_narration_key() {
        let catalog = default_categories();
        let merchants = vec![MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Literal,
            pattern: "swiggy".to_string(),
            category: builtin("FOOD_AND_DINING"),
        }];
        // "UPI-SWIGGY-123456" normalizes to "swiggy-123456" → the literal "swiggy" hits.
        let d = run(
            &txn(false, Direction::Debit, "UPI-SWIGGY-123456"),
            &catalog,
            &merchants,
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(d.stage, Stage::T2MerchantMap);
        assert_eq!(d.category_ref, builtin("FOOD_AND_DINING"));
    }

    #[test]
    fn t2_regex_pattern_is_lowercased_like_the_web() {
        // The web `merchant_identity` lowercases the alias pattern before `re.search`, so an
        // UPPERCASE regex must still match the (lowercased) normalized narration.
        let catalog = default_categories();
        let merchants = vec![MerchantRule {
            priority: 10,
            match_type: MerchantMatch::Regex,
            pattern: "AMAZON|AMZN".to_string(),
            category: builtin("SHOPPING"),
        }];
        let d = run(
            &txn(
                false,
                Direction::Debit,
                "POS AMZN RETAIL BANGALORE 9876543210",
            ),
            &catalog,
            &merchants,
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(d.stage, Stage::T2MerchantMap);
        assert_eq!(d.category_ref, builtin("SHOPPING"));
    }

    #[test]
    fn uncategorized_when_no_stage_matches() {
        let catalog = default_categories();
        assert!(run(
            &txn(false, Direction::Debit, "UNKNOWN VENDOR XYZ"),
            &catalog,
            &[],
            &[],
            &[],
        )
        .is_none());
    }

    #[test]
    fn cc_rule_ignores_a_custom_category_sharing_a_builtin_name() {
        // A user's *custom* category that happens to be named "Credit Card Bill Payment"
        // must not hijack the CC rule — it still resolves to the built-in code.
        let mut catalog = default_categories();
        catalog.push(Category {
            category_ref: CategoryRef::Custom {
                id: "my-cc".to_string(),
            },
            name: "Credit Card Bill Payment".to_string(),
            classification: Some(Classification::CcPayment),
        });
        let d = run(
            &txn(false, Direction::Debit, "ICICI CREDIT CARD PAYMENT"),
            &catalog,
            &[],
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(d.stage, Stage::CcRule);
        assert_eq!(d.category_ref, builtin("CREDIT_CARD_BILL_PAYMENT"));
    }

    #[test]
    fn an_uncompilable_rule_regex_is_skipped_not_fatal() {
        // A rule whose regex will not compile must be skipped (never matches, never panics),
        // and a later well-formed rule still fires.
        let catalog = default_categories();
        let rules = vec![
            Rule {
                id: Some("broken".to_string()),
                priority: 10,
                is_system: true,
                match_type: RuleMatch::Regex,
                value: "(".to_string(),
                category: builtin("SHOPPING"),
            },
            Rule {
                id: Some("good".to_string()),
                priority: 20,
                is_system: true,
                match_type: RuleMatch::Keyword,
                value: "fallback".to_string(),
                category: builtin("MISCELLANEOUS"),
            },
        ];
        let d = run(
            &txn(false, Direction::Debit, "FALLBACK VENDOR"),
            &catalog,
            &[],
            &rules,
            &[],
        )
        .unwrap();
        assert_eq!(d.matched_rule_id.as_deref(), Some("good"));
        assert_eq!(d.category_ref, builtin("MISCELLANEOUS"));
    }

    #[test]
    fn custom_category_ref_is_echoed_from_the_facts() {
        let catalog = default_categories();
        let rules = vec![Rule {
            id: Some("r".to_string()),
            priority: 10,
            is_system: false,
            match_type: RuleMatch::Keyword,
            value: "tuition".to_string(),
            category: CategoryRef::Custom {
                id: "user-school-fees".to_string(),
            },
        }];
        let d = run(
            &txn(false, Direction::Debit, "TUITION FEE"),
            &catalog,
            &[],
            &rules,
            &[],
        )
        .unwrap();
        assert_eq!(
            d.category_ref,
            CategoryRef::Custom {
                id: "user-school-fees".to_string()
            }
        );
    }

    #[test]
    fn is_deterministic() {
        let catalog = default_categories();
        let t = txn(true, Direction::Credit, "10% Swiggy Cashback");
        assert_eq!(
            run(&t, &catalog, &[], &[], &[]),
            run(&t, &catalog, &[], &[], &[])
        );
    }
}
