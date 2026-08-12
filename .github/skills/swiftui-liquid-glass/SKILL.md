---
name: swiftui-liquid-glass
description: Implement, review, or improve Kaname's SwiftUI UI using the iOS 26 Liquid Glass API. Use when building any new screen or control, refactoring an existing view to Liquid Glass, or reviewing glass usage for correctness, performance, and design alignment. Triggers on glassEffect, GlassEffectContainer, .buttonStyle(.glass), toolbars, tab bars, sheets, cards, chips, "make this feel native", "adopt Liquid Glass".
---

# SwiftUI Liquid Glass

Liquid Glass is the iOS 26 material: it blurs what's behind it, picks up colour and light
from surrounding content, reacts to touch, and morphs between shapes across hierarchy
changes. **This is Kaname's default surface treatment** — every new screen uses the native
APIs rather than hand-rolled blur.

Deep reference (API surface, every modifier, worked examples): `references/liquid-glass.md`.
Read it before non-trivial work; the rules below are the ones that decide reviews.

## Kaname's baseline: iOS 26 minimum, no fallbacks

The app's deployment target is **iOS 26.0** (`ios/Project.swift`,
`core/scripts/build-xcframework.sh`). That is deliberate — it buys unconditional Liquid Glass.

- **Never write `#available(iOS 26, *)`** around a glass modifier. It's dead code here, and a
  fallback branch doubles the UI surface that has to be reviewed and tested.
- **Never hand-roll glass.** No `.ultraThinMaterial` stacks, no `UIVisualEffectView`, no
  custom blur+gradient imitations. If you reach for one, the answer is a native glass API.
- Standard components (toolbars, tab bars, sheets, navigation) get Liquid Glass **for free**
  from the SDK. Don't re-skin them; let the system own its own chrome.

## Where glass goes — and where it doesn't

Reach for glass on **floating surfaces that sit above content**: action buttons, chips and
filter pills, badges, cards that overlay a scroll view, custom toolbars.

Do **not** glass:

- **Dense data.** The transaction list, statement rows, and any table of numbers stay on
  opaque backgrounds. Glass over scrolling text is a legibility and performance tax for no gain.
- **Backgrounds.** Glass is a foreground material; it needs content behind it to refract.
- **Everything.** If most of a screen is glass, nothing reads as elevated. Glass earns its
  place by contrast with flat content.

## Core rules

- **Order matters:** apply `.glassEffect(...)` **after** layout and appearance modifiers
  (padding, frame, font). Applying it early glasses the wrong bounds.
- **Group with `GlassEffectContainer`:** two or more glass views in the same region belong in
  one container. It's both the performance path and the only way effects blend and morph.
  `spacing:` controls how close elements must be before their effects merge.
- **`.interactive()` only where there is interaction.** A tappable chip: yes. A static badge:
  no. Interactive glass on a non-interactive element is a lie the user feels.
- **Morphing needs identity:** `@Namespace` + `.glassEffectID(_:in:)` on each participant, and
  the hierarchy change must happen inside `withAnimation`. Without the ID, views cross-fade
  instead of morphing.
- **Buttons use the built-in styles:** `.buttonStyle(.glass)`, or `.buttonStyle(.glassProminent)`
  for the single primary action on a screen. Don't build a glass button out of a glassed
  `Text` with a tap gesture.
- **Consistent shapes:** related elements share a shape and corner radius
  (`in: .rect(cornerRadius:)` or the default `.capsule`). Mixed radii inside one container is
  the most common thing that makes a glass screen look wrong.
- **Tint sparingly.** `.tint(_:)` signals prominence; more than one tinted glass element per
  screen and prominence stops meaning anything.

## Money-specific

Kaname renders currency everywhere, and glass moves under the text it hosts.

- Amounts on glass use **`.monospacedDigit()`** so figures don't jitter while the material
  animates (see `make-interfaces-feel-better` → typography).
- Never place a **red/green amount** on a **tinted** glass surface — the tint shifts the hue
  and the debit/credit signal degrades. Tint the container or the amount, never both.
- Respect **Reduce Transparency** and **Increase Contrast**: check that amounts still meet
  contrast when the system substitutes an opaque material. Dynamic Type and VoiceOver apply
  as always (Constitution: accessibility is not optional).

## Review checklist

- [ ] No `#available(iOS 26, *)` gates, no fallback branch, no hand-rolled blur.
- [ ] Multiple glass views in a region share a `GlassEffectContainer`.
- [ ] `.glassEffect` sits after layout/appearance modifiers.
- [ ] `.interactive()` appears only on genuinely interactive elements.
- [ ] Morphing transitions carry `glassEffectID` + `@Namespace` and animate the hierarchy change.
- [ ] Shape, corner radius, and tint are consistent across related elements; at most one
      prominent/tinted element per screen.
- [ ] Dense lists and numeric tables are **not** glassed.
- [ ] Amounts use `monospacedDigit`; contrast holds under Reduce Transparency / Increase Contrast.
- [ ] Nothing new re-skins system chrome (toolbar / tab bar / sheet).

## Snippets

```swift
Text("Hello")
    .padding()
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
```

```swift
GlassEffectContainer(spacing: 24) {
    HStack(spacing: 24) {
        Image(systemName: "scribble.variable")
            .frame(width: 72, height: 72)
            .font(.system(size: 32))
            .glassEffect()
        Image(systemName: "eraser.fill")
            .frame(width: 72, height: 72)
            .font(.system(size: 32))
            .glassEffect()
    }
}
```

```swift
Button("Confirm") { }
    .buttonStyle(.glassProminent)
```

## Related

- `make-interfaces-feel-better` — the general polish pass (typography, animation, surfaces).
  Liquid Glass is the material; that skill is the craft applied on top of it.
- `apple-appstore-reviewer` — run before submission; HIG alignment is a review axis.

---

Adapted for Kaname from [Dimillian/Skills](https://github.com/Dimillian/Skills)
(`swiftui-liquid-glass`), MIT licensed. `references/liquid-glass.md` is vendored from that
repo; this `SKILL.md` is rewritten for Kaname's iOS 26 baseline (the upstream version assumes
availability gating and fallbacks, which this project does not use).
