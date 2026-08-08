# An account is required to use the app

Using Kaname requires creating an account, reversing the earlier "no account required"
stance. The account stores only identity, entitlement (free/Pro) and minimal first-party,
account-scoped usage signals — never the user's financial data, which stays on-device and
encrypted. We accept this because it enables entitlement enforcement (free vs Pro) and
future account-based features (cross-device sync), and because the core engine remains
network-free so the privacy-egress guarantee is unaffected.

## Consequences

- The app is no longer usable fully anonymously/offline from first launch (sign-in needs
  the network once).
- **App Store Guideline 5.1.1(v) risk**: Apple discourages forcing login when free
  features don't need an account. Mitigation: justify the account via Pro/sync/entitlement
  (account-based features), offer Sign in with Apple, and consider a local/guest mode if
  Review pushes back.
- The privacy claim narrows from "nothing leaves the device / no account" to "financial
  data stays on-device on every free path; the account holds identity + minimal usage".
