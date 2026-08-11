# 06 — Transfer → category assignment (deferred from slice 03)

**Status:** needs-triage

**What to build:** the piece slice 03 (`03-transfer-persistence.md`) deliberately deferred.
Slice 03 tags transfer legs (`is_transfer` + `transfer_group_id`) but assigns **no category**.
This slice assigns the transfer category — **Self Transfer** (`SELF_TRANSFER`) or **Credit Card
Bill Payment** (`CREDIT_CARD_BILL_PAYMENT`), both already seeded builtins — to tagged legs, and
settles the **categorize-vs-transfer precedence** the tag-only decision punted. No engine
changes to the pure matcher. Design of record: `.scratch/persistence/spec.md`;
`03-transfer-persistence.md` ("Scope decision — tag-only"); `categorize.rs` `default_categories()`.

**Blocked by:** #02 categorization write-back (done) + #03 transfer persistence (done). Unblocked
once triaged.

## Open decision (settle with the user before implementing)

1. **Precedence — the clobber problem.** `store.categorize_account` re-runs over **all**
   non-deleted rows and currently sets `category_id` unconditionally (even to NULL on no-match),
   so it would **overwrite** a transfer-assigned category on the next run. Decide the contract:
   does `categorize_account` **skip `is_transfer` rows**? Does transfer assignment **win** and
   categorize leave it? What's the order of operations on import?
2. **Where the assignment lives.** Extend `detect_transfers` to also set `category_id` (couple
   them in one pass, like the web `transfer_detector`), vs a separate
   `store.assign_transfer_categories()`, vs making `categorize_account` transfer-aware. The
   `is_credit_card_payment` split already surfaces in slice 03's `TransferSummary`.

## Sketch (post-triage)

- No new schema (both categories are seeded; `is_transfer`/`transfer_group_id`/`category_id`
  all exist).
- Assign `CREDIT_CARD_BILL_PAYMENT` when the pair had a CC leg, else `SELF_TRANSFER`; honour the
  precedence rule above so a re-run is idempotent and doesn't clobber.
- Behavioural tests (temp DB): a CC bill-payment pair ⇒ both legs `CREDIT_CARD_BILL_PAYMENT`; a
  bank-to-bank pair ⇒ `SELF_TRANSFER`; a `categorize_account` re-run does **not** clobber; a
  non-transfer row is unaffected.

## Deferred
Manual un-tagging/override of a mistaken transfer (arrives with the learning/correction work).
