# Triage Labels

The skills speak in terms of five canonical triage roles. This repo tracks issues as local markdown, so each role is recorded as the `Status:` value near the top of an issue file (see `issue-tracker.md`). This file maps the canonical roles to the strings used here.

| Label in mattpocock/skills | Status in our tracker | Meaning                                  |
| -------------------------- | --------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`        | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`          | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`     | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`     | Requires human implementation            |
| `wontfix`                  | `wontfix`             | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), write the corresponding string from this table as the issue's `Status:`.

Edit the right-hand column to match whatever vocabulary you actually use.
