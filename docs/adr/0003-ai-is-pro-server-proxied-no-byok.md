# AI is a Pro, server-proxied feature (no BYOK)

All AI features (LLM statement parsing for unrecognized layouts, AI categorization/assist)
are Pro-only and run through Kaname's server-proxied managed AI; there is no
bring-your-own-key path in the client. We dropped BYOK because supporting many LLM
providers/keys in the client is disproportionate effort and would put an AI path on the
free tier. The **free** fallback for an unrecognized statement is the on-device manual
column-mapper.

## Consequences

- `kaname-core` stays pure: it may build the extraction prompt and parse/validate the
  model's JSON (reusing balance-chain / reconcile), but the network call lives server-side.
- When a Pro user opts into AI parsing, redacted statement text (card numbers masked)
  leaves the device to Kaname's backend — an explicit, consented Pro action.
