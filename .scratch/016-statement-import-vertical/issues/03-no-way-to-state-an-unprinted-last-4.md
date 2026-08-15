# 03 — A person cannot give an account the last-4 the statement did not print

**Status:** needs-triage

**Found:** 2026-08-15, on a real iPhone, importing a synthetic SBI card statement during 018's
manual gate: *"for SBI it asked me to create account but no option to put the account last 4
digit."*
**Belongs to:** `016-statement-import-vertical` — `AccountPickerView` and FR-024 are its code
and its requirement.
**Severity:** Not a defect against the spec. **The spec is what is thin**, so this needs a
product decision rather than a fix.

## What happens

An SBI card statement masks all but **two** digits (`XXXX XXXX XXXX XX61`), so the engine
recovers **no** last-4. With no existing SBI account, FR-024 sends the person to
`AccountPickerView`, whose "add a new one" section offers exactly one field — `Account name`
(`ios/Sources/Import/AccountPickerView.swift:47`) — and creates the account with `last4: nil`.

That is precisely what FR-024 asks for: *"the app MUST ask the person to **pick or name** the
account"*. The implementation matches the requirement. The requirement never considered that a
person might know a number the document did not print.

## What it costs, downstream

- The account has **no identity digits, permanently**. There is no account-editing UI anywhere
  in the app, so `last4` cannot be filled in later by any means.
- On the transaction list and the front door it shows as a bare name — FR-003 renders no
  "ending ••••" for it, correctly, because there is nothing to render.
- Future SBI statements still attach correctly, but via the weakest rule in the matrix: *the
  single account for this issuer that never learned its own last-4* (FR-024). **Add a second SBI
  card and that rule cannot fire** — the app must then ask on every import, and the two accounts
  are indistinguishable in the picker, both being a name with no digits.

## Why it is a decision and not an obvious fix

There is a real argument on each side, and the app's whole stance on identity is at stake:

- **For a field:** the person is holding the card. Kaname refusing to record what they plainly
  know is the app being pedantic at their expense, and it degrades every future import for that
  issuer.
- **Against:** a typed last-4 is **unverified data used for matching**. A typo silently
  mis-attributes a future statement to the wrong account — the exact class of silent error this
  vertical was built to prevent — and it would sit in the same column as digits the engine read
  off a document, indistinguishable from them.

A middle path exists: accept a typed last-4 but **record its provenance** (read vs. stated), let
only a *read* value win a match outright, and let a *stated* one be corrected the first time a
document for that account prints digits of its own. That costs a column and a rule.

## Not to be resolved by an agent unasked

Whichever way it goes changes what an account *is* — `data-model`'s Account gains either a field
or a provenance — so it wants a human decision first. If a field is added it must also answer:
what does it validate (4 digits? the 2 the statement did show?), and does an account created
with a stated last-4 still match a later statement that prints a different one.
