# 06 — Transfer → category assignment (deferred from slice 03)

**Status:** resolved (shipped — transfer-wins precedence + category assignment in `detect_transfers`)

**What to build:** the piece slice 03 (`03-transfer-persistence.md`) deliberately deferred.
Slice 03 tags transfer legs (`is_transfer` + `transfer_group_id`) but assigns **no category**.
This slice assigns the transfer category — **Self Transfer** (`SELF_TRANSFER`) or **Credit Card
Bill Payment** (`CREDIT_CARD_BILL_PAYMENT`), both already seeded builtins — to tagged legs, and
settles the **categorize-vs-transfer precedence** the tag-only decision punted. No engine
changes to the pure matcher. Design of record: `.scratch/persistence/spec.md`;
`03-transfer-persistence.md` ("Scope decision — tag-only"); `categorize.rs` `default_categories()`.

**Blocked by:** #02 categorization write-back (done) + #03 transfer persistence (done). Unblocked
once triaged.

## Settled decisions (triage)

1. **Precedence → transfer wins.** `categorize_account` **skips rows where `is_transfer = 1`**,
   leaving their `category_id` / `categorised_by` untouched (and not counting them as
   uncategorized). A confirmed cross-account pair — two rows on two accounts agreeing on date,
   amount and opposite direction — is stronger evidence than a keyword match, so the rule is
   enforced in code rather than documented as an ordering contract. Import order stays free: a
   `categorize_account` re-run can never clobber a transfer category, whichever ran first.
2. **Assignment lives in `detect_transfers`.** The pass that mints the `transfer_group_id` also
   writes `category_id` (`CREDIT_CARD_BILL_PAYMENT` when the pair had a credit-card leg, else
   `SELF_TRANSFER`) and `categorised_by = 'TRANSFER_DETECTOR'`, in the same write transaction —
   mirroring the web `transfer_detector`, with no second call to forget. The existing
   `WHERE … transfer_group_id IS NULL` guard keeps it idempotent.

## Sketch

- No new schema: both categories are seeded builtins, and
  `is_transfer`/`transfer_group_id`/`category_id`/`categorised_by` all exist.
- `detect_transfers`' UPDATE also sets `category_id` + `categorised_by`; the CC/self split comes
  from `TransferPair.is_credit_card_payment`, which the matcher already returns.
- `load_account_transactions` (the categorize candidate loader) gains `AND is_transfer = 0`.
- Behavioural tests (temp DB): a CC bill-payment pair ⇒ both legs `CREDIT_CARD_BILL_PAYMENT`; a
  bank-to-bank pair ⇒ `SELF_TRANSFER`, both `categorised_by = 'TRANSFER_DETECTOR'`; a
  `categorize_account` re-run does **not** clobber (either order); a non-transfer row still
  categorizes normally; the skipped rows aren't counted in `CategorizeSummary`.

## Deferred
Manual un-tagging/override of a mistaken transfer (arrives with the learning/correction work).
