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
