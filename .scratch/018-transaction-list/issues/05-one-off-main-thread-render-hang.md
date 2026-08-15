# 05 — A one-off main-thread render hang at 100% CPU, sampled but not yet reproduced

**Status:** needs-info

**Found:** 2026-08-15, on the simulator (iPhone 16, iOS 26.5, Debug build), once, during the
manual gate. **Three deliberate attempts to reproduce it failed** — see below.
**Belongs to:** unattributed. The sampled stack is entirely SwiftUI/UIKit; no Kaname frame
appears in the hot path, so which of our views provoked it is exactly what is unknown.
**Severity:** ⛔ A frozen app. If it is reachable in a shipping build it is release-blocking; if
it is a simulator artefact it is noise. **Deciding which is the whole content of this ticket.**

## What happened

Immediately after picking `4-corrupt.pdf` from the document picker, the app stopped responding
to all touches. It never showed the failure screen; it sat on the accounts list. CPU went to
**99–100% and stayed there** for over ninety seconds, until the process was terminated. It
recovered completely on relaunch (3.4% CPU), so nothing was persisted wrong.

## What the sample says

`sample` over three seconds (`hang-sample.txt` in the session evidence) puts **1217 of 1217**
main-thread samples inside a single, never-completing `CATransaction` commit:

```
CA::Transaction::commit()
  CA::Layer::layout_and_display_if_needed
    -[UIView(CALayerDelegate) layoutSublayersOfLayer:]
      _UIHostingView.layoutSubviews()
        ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:)
          ViewGraph.renderDisplayList(...)
            DisplayList.ViewUpdater.updateInheritedView(container:from:parentState:)
              DisplayList.ViewUpdater.updateItemView(container:from:localState:)
                -[UIView(Internal) _addSubview:positioned:relativeTo:]
                  -[UIView _postMovedFromSuperview:]
                    -[UIView(Internal) _didMoveFromWindow:toWindow:]   ← nested dozens deep
```

The remaining cost is `_normalInheritedTintColor` / `_ancestorTintColor` /
`CA::Layer::collect_layers_` — tint resolution over a very large layer tree.

**Read plainly:** SwiftUI was rebuilding an enormous view hierarchy from scratch, on the main
thread, inside one commit, and the run loop never turned. No Rust, no PDFKit, no import work
appears anywhere — the engine and the extractor are ruled out by the sample itself.

## What was ruled out

Each was attempted after a clean relaunch:

| Hypothesis | Result |
|---|---|
| Importing `4-corrupt.pdf` at largest text size | ❌ failure screen appeared normally |
| …after scrolling the transaction list deep (thousands of rows loaded), then going back | ❌ no freeze |
| A **live** Dynamic Type change with a deeply-scrolled list on screen | ❌ 0% CPU, no freeze |

## What the state was when it did happen, in full

Every one of these was true at once, which is why none of the single-variable retries settled it:

- Reduce Transparency had been switched **on while the app was running**.
- Content size had been changed **live**, `large` → `accessibility-XXXL`, while the app ran.
- The transaction list had been **filtered** to one account **and** scrolled ~3,000 rows deep,
  into December 2025, then dismissed back to the front door.
- Four accounts, 5,000 live rows.
- Debug build, launched by `simctl`.

The untested combination is **two live trait changes** (Reduce Transparency *and* content size)
against a large, filtered, deeply-paged list.

## What closing this takes

1. Re-run the above in that order, deliberately, and see whether it reproduces.
2. If it does, capture a sample and bisect by removing one condition at a time.
3. If it does not reproduce in a Release build on a device, downgrade to `wontfix` **with the
   sample kept** — an unreproducible freeze that only ever appeared under `simctl`-driven trait
   changes in a Debug simulator build is a plausible simulator artefact, and saying so with
   evidence is a real answer.

⚠️ Do not close this as "could not reproduce" without step 3. The stack is a real pathology
whether or not we caused it.
