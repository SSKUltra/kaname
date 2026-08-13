# Unknown-bank ingestion: fallback ladder, learned signatures, and opt-in contribution

## Context

Kaname ships static readers for a fixed set of Indian banks/cards, but users will upload
statements from issuers we don't yet support — and we can't acquire every bank's layout
upfront. We need to (a) never block the user, (b) let the maker eventually build a static
reader for the missing issuer — all under Constitution Principle I (no silent telemetry;
financial data stays on-device) and the Free/Paid boundary (Principle VI; AI is Pro).

## Decision

A layered recognition + fallback strategy, all detection on-device:

1. **Detection.** Every reader's `claims()` runs locally; a statement that **no** reader
   claims is *unrecognized*. This is never reported anywhere automatically.
2. **Recognition order:** built-in readers → **learned signatures** → **fallback ladder**.
3. **Fallback ladder** for an unrecognized statement:
   - **Free — on-device manual mapper.** The user maps date / amount / description /
     direction from the extracted table. Zero network; never blocks the user (the floor).
   - **Pro — server-proxied AI parse.** Opt-in; statement text is *extraction-redacted*
     (card/PAN masked, amounts + merchant text kept) before it leaves the device; the
     result is validated (`balance_chain` / `reconcile`, already ported) before its rows
     are trusted. No BYOK.
4. **Signature-learning.** After a successful mapper/AI parse, derive a structure-only
   **layout signature** (date format, column positions / row shape, header & marker
   tokens, currency, card-vs-ledger kind — **no values**). It becomes a per-user
   **learned reader**, so the same issuer parses deterministically on later imports with
   no mapper and no AI cost. Self-healing: a layout change stops the match and relearns.
   The core stays pure (`derive_signature` / `signature_matches` / `read_with_signature`);
   the platform stores signatures. A signature-parsed statement is still validated before
   trust (never silently mis-parse financial data).
5. **Contribution.** Because a signature carries no values, it is PII-free by construction
   and *is* the contribution unit — a raw statement never leaves the device for
   contribution. Sharing is **explicit opt-in only**, never silent.
   - *Phase 1:* out-of-band export — the client writes the signature to a file the user
     shares themselves (share sheet → prefilled GitHub issue / email). The client makes
     **zero** network calls; no constitution change needed.
   - *Phase 2 (later):* an opt-in in-app submit to Kaname's backend. This is a new
     networked path, so it requires a small Principle I amendment; it stays **free** (a
     signature is not financial data).
6. **Maker pipeline.** Contributed signatures are deduped, **prioritized by frequency**
   (which unsupported issuers hit the most users), then a maker authors a static reader
   **+ a synthetic golden fixture** and ships it via the normal per-slice flow.
7. **Sync.** Learned signatures are local-only while free; when Pro cross-device sync
   ships, they ride along as user data (no separate mechanism).

## Consequences

- **Two distinct redactions:** *Extraction redaction* (light — for the Pro AI path, keeps
  amounts/merchants) vs *Contribution* (a signature — structure-only). Don't conflate them.
- **Constitution ties:** Phase-2 in-app contribution submit needs a Principle I amendment
  (a new permitted networked path). Golden fixtures MUST stay synthetic (Principle V) — a
  contributed signature guides authoring but is never committed as test data.
- **New pure core surface:** `derive_signature`, `signature_matches`, `read_with_signature`,
  plus the mapper's `read_with_mapping`, and the AI path's prompt-builder / response-parser
  (network call stays native/server-side). All deterministic, all golden-testable.

---

## Amendment (2026-08-13): a signature *generates* fixtures; and the trigger is too narrow

### Context

Slice 017 (`specs/017-column-major-pdf/`) was opened after running thirteen genuine
statement PDFs through the shipped pipeline. Two findings bear directly on this ADR.

### Change 1 — a signature is a fixture *generator*, not merely authoring guidance

The Consequences section above says a contributed signature "guides authoring but is never
committed as test data". That was too conservative, and it conflated two different things.

A signature carries **no values** (§5). So a signature can be **rendered back into a
statement document** with entirely fabricated merchants, amounts, dates and account numbers,
placed at the signature's real column positions and row spacing. The resulting document is
**synthetic by construction** — every byte of its content is invented — while its *geometry*
is faithful to the contributed layout. It is therefore committable under Principle V, and the
signature is committable alongside it.

This was validated end-to-end before amending: a signature derived from a real Yes/Kiwi card
statement (35 column positions, 21.3pt row spacing, date shape `99/99/9999`) was rendered into
a synthetic statement carrying four fabricated transactions. Run through the shipped pipeline,
it reproduced the production bug exactly — `detect_issuer` returned `YES_KIWI_CARD`
(then named `YES_CARD`), the printed
totals were recovered (3050.00 Dr / 5000.00 Cr), and the reader returned **0 of the 4 printed
transactions**, because the amount column arrived on its own text lines.

Two things follow, and they are why this matters more than convenience:

- **A generated fixture exercises the native extractor end-to-end.** Every fixture in
  `fixtures/` today supplies pre-split `lines`, so it tests the readers while assuming the
  extraction that actually failed. A generated document is opened by the real PDF engine, so
  the extractor is under test too. This is the specific blind spot that let eighteen green
  fixtures coexist with total failure on real statements.
- **It gives contribution a testable output.** A contributor's signature becomes a committed
  synthetic document plus its golden vector, so an unsupported issuer arrives with its own
  regression test rather than a description of one.

What is still forbidden is unchanged and absolute: **the real statement, and any value taken
from it, never enters the repository.** A generated fixture must be reviewed to confirm it
carries no token lifted from the source document — header and marker literals come from the
reader's own published claim markers, never harvested from a contributor's file.

**Non-vacuity rule.** A generated fixture that passes against the extractor it was meant to
fix proves nothing. Each one MUST be demonstrated to fail before the fix and pass after
(mirrored in slice 017 as FR-037/SC-011).

### Change 2 — the fallback ladder's trigger misses the dominant failure

The ladder in §3 is entered by a statement that **no reader claims** (*unrecognized*). The
reference set shows that is not the common case: **eight of the thirteen files were recognised
correctly and still read zero transactions.** A claimed-but-unreadable statement never enters
the ladder — it gets no mapper, learns no signature, and yields no contribution. The app
simply reports a statement with no spending, which is precisely the silent-wrong-answer this
ADR exists to prevent.

**Decision:** the ladder is entered by an *unusable parse*, not merely an unclaimed one. A
statement that a reader claims but from which it recovers no transactions — or whose recovered
rows fail `reconcile` / `balance_chain` validation — is unusable, and MUST offer the same
ladder (manual mapper → signature learning → contribution) as an unrecognized one. Detection
of an unusable parse stays on-device and is never reported anywhere automatically; §1's rule
that nothing leaves the device without explicit opt-in is unchanged.

Slice 017 fixes the extractor for the ten currently-supported issuers. This trigger change is
what makes the ladder reachable for the eleventh bank and beyond, and is scoped to its own
slice.

---

## Amendment (2026-08-13, second): the contributor must be able to *see* what they share

### Context

Review of the amendment above asked a question this ADR had never answered: when a person is
invited to contribute, how do they know that what leaves their phone is not their financial
data? §5 asserts a signature is "PII-free by construction" and §1 forbids silent reporting.
Both are properties of the *implementation*. Neither is visible to the person being asked.

For an app whose entire promise is that statements never leave the device, asking someone to
upload anything derived from a bank statement — without showing them exactly what — is a trust
failure regardless of how safe the payload actually is. Informed consent under DPDP is also not
satisfied by a correctness claim the user cannot inspect.

### Decision

Contribution is **inspectable, not merely opt-in**. Whatever the transport (Phase 1 share
sheet, Phase 2 in-app submit), the following hold:

1. **The exact payload is shown before it is shared.** Not a description of it, not a summary —
   the actual, complete artefact that would leave the device, legible in the app. If a person
   cannot read it, it is not ready to be shared.
2. **The payload is stated in plain language**, in the copy deck alongside every other import
   sentence (`ios/Sources/Import/ImportModels.swift`): what a layout signature is, that it
   records where columns sit and what shape the dates are, and that it contains **no amounts,
   no merchant names, no account numbers and no dates from the statement**.
3. **Contribution is refusable and revocable at the point of asking**, and refusing costs the
   person nothing — the manual mapper (§3) remains the free floor, so a declined contribution
   never blocks an import.
4. **Nothing is pre-selected and nothing is bundled.** Contribution is never a side effect of
   importing, of learning a signature, or of any other action.
5. **A generated dummy statement may be the contributed artefact, at the contributor's
   choice.** A synthetic document rendered on-device from the signature (per the first
   amendment) is *more* inspectable than the signature itself: the person can open it and see
   fabricated merchants and amounts that are visibly not theirs. Where a dummy statement is
   offered, the signature it was generated from is shown too — the dummy statement must never
   be the only thing the person is allowed to inspect.
6. **The claim is testable, not asserted.** The payload builder is a pure core function with
   golden vectors proving that no value from the source statement survives into it — the same
   standard `make import-audit` applies to networking symbols. "PII-free by construction" must
   be a passing test, not a comment.

### Consequences

- Contribution is a **UI slice**, not only an engine one: it needs screens, copy and an
  accessibility pass, and it inherits slice 016's rules (no engine-supplied strings on screen
  except `Issuer.display_name`; every failure and state sentence lives in the copy deck).
- Phase 2's Principle I amendment must carry these guarantees, not just permit the network path.
- Slice 017 is still a prerequisite: a signature derived from fragmented column-major text
  would record a broken layout, and showing a person a faithful-looking artefact built from a
  layout we read wrongly would make the transparency guarantee hollow.

---

## Amendment (2026-08-13, slice 017): `issuer_id` is not yet persisted

Slice 017 renamed the registry's entries so a card is named by its **product** and a bank by
its **bank** (`<INSTITUTION>_<PRODUCT>_CARD` / `<INSTITUTION>_BANK`). The id a statement was
recognised as is **deliberately not written to the store** — the schema stays at v6 and an
account still carries only its bank code.

**Why deferred.** Nothing in this slice reads a persisted `issuer_id`: recognition happens on
every import, from the document itself. Adding a column would have meant a v7 migration inside
a slice whose subject is extraction, and a migration is the one thing that cannot be revised
once a person's database has run it.

**Why it must land before first release.** Once a real database exists, back-filling the id of
a statement already imported means re-recognising a document that is no longer on the device.
The window in which this is free closes at first release, and it must land inside it.

Recorded in `specs/017-column-major-pdf/research.md` R9.

