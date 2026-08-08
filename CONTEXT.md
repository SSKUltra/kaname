# Kaname — Domain Glossary

Ubiquitous language for Kaname's on-device finance engine. Definitions are domain-level,
not implementation notes. Kept as a glossary only — decisions live in `docs/adr/`.

## Statement ingestion

**Reader**:
A per-issuer parser that turns one bank/card statement's extracted text into transactions.
_Avoid_: parser (when you mean the issuer-specific one), importer

**Claim**:
A reader *claims* a statement when it recognises the layout as its own issuer's. Detection
is running every reader's claim check; it happens entirely on-device.
_Avoid_: match, detect

**Unrecognized statement**:
A statement that **no** reader claims — the trigger for the fallback ladder. Detected
locally; never reported anywhere automatically.
_Avoid_: unknown bank, unsupported statement

**Fallback ladder**:
What an unrecognized statement falls through, in order: the free on-device **manual
mapper**, then the **Pro AI parse**. The user is never blocked from importing.

**Manual mapper**:
The free, on-device escape hatch: the user maps date / amount / description / direction
from the extracted table so any statement imports without a built-in reader. Zero network.
_Avoid_: CSV importer

**Contribution**:
A redacted, structure-only sample the user *explicitly chooses* to share so Kaname can
build a static reader for that issuer. The only way the maker ever learns a bank is
unsupported — never automatic, never silent.
_Avoid_: telemetry, report, phone-home

**Signature** (layout signature):
A structure-only fingerprint of a statement's layout — date format, column positions /
row shape, header and marker tokens, currency, card-vs-ledger kind. Carries NO values
(no amounts, names, dates-as-data, or account numbers), so it is PII-free by construction
and safe to contribute. A statement parsed via a signature is still validated
(balance-chain / reconcile) before its rows are trusted.
_Avoid_: template, schema, fingerprint (unqualified)

**Learned reader**:
A per-user deterministic reader built from a learned Signature. Checked after built-in
readers and before the fallback ladder, so a once-unrecognized statement parses without
the mapper or AI on later imports. Self-healing: if the issuer changes its layout the
signature stops matching and the statement simply relearns.
_Avoid_: custom parser, user rule

**Extraction redaction**:
The light masking applied only on the Pro AI path before statement text is sent to the
model — card / PAN numbers are masked, but amounts and merchant text are kept so the
model can extract transactions. Distinct from a Contribution, which shares only a Signature.
_Avoid_: redaction (unqualified)

## Categorization

**Category**:
A user-facing label assigned to a transaction (e.g. "Groceries"). Kaname ships 23 defaults;
a transaction has at most one.
_Avoid_: tag (tags are a separate, multi-valued concept)

**Classification**:
The rename-proof money-bucket a Category rolls up to for analytics — one of SPEND, INCOME,
INVESTMENT, TRANSFER, CC_PAYMENT, REFUND (or none → fall back to Direction). Distinct from
the Category's name.
_Avoid_: type, kind, bucket

**Categorization stack**:
The ordered, first-wins pipeline that assigns a Category: CC rules → source-category map
(T1) → merchant map (T2) → rules (T3) → LLM (T4). The four deterministic stages are the
free on-device port; **T4 is Pro** (server-side).

**Source-category map** (T1):
A per-issuer mapping from a statement's own category field to a Kaname Category.

**Merchant map** (T2):
The "memory": a per-user mapping from a normalized narration to a Category, learned from
the user's own past categorizations. Keyed on the same normalized narration as dedup.
_Avoid_: history

**Rule** (T3):
A user or system rule that assigns a Category by matching the narration or amount — KEYWORD
(case-insensitive substring), REGEX, or AMOUNT_RANGE — resolved by priority (lower wins).
_Avoid_: filter

**CC rules**:
India-specific narration heuristics (no stored state) that run *before* the tiers to catch
credit-card bill payments and card inflows.
