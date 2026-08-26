# AGENTS.md

Guidance for humans and coding agents working on Kaji.

## What Kaji is

Kaji is a **truncatable macOS menu-bar module host**.

**Long-term goal:** the menu bar **worth keeping** in the AI era — quiet enough to stay, not “the only bar that does everything.”

- Default should feel **small and quiet** (quota rings first).
- Extra capabilities (work/break, system, goals, heavy break theater) are **opt-in modules**, not a forced bundle.
- “All-in-one” means **one shell, assemble what you want** — not install-once-get-everything.
- **Worth keeping ≠ kitchen sink.** Do not chase exclusivity by piling surfaces.

Product direction + architecture decisions:

- [docs/product-principles.md](docs/product-principles.md)
- [docs/module-architecture.md](docs/module-architecture.md)

## North star (read this first)

Real user signal:

> Latest updates piled on too much. It used to be small and beautiful — I rolled back.

So:

1. **Prefer removing drama over adding surfaces.**
2. **Modules exist so the product can get small again**, not so it can grow forever.
3. Do **not** chase Ice/Bartender (hiding other apps’ menu-bar icons) in this phase.
4. Do **not** build a remote plugin marketplace yet. First-party toggles first.

## Current branch policy

- Lean-modules v1 shipped on `main`; new work stays incremental and reversible.
- WIP feature experiments stay parked until they fit an opt-in module.
- Changes land through a feature branch and pull request; do not push work directly to `main`.
- Before merging, wait for every required GitHub Actions check to complete successfully. A local build or test run does not replace CI.
- Merge only after CI is green, then return to a fresh branch for further optimization.

## Documentation layers

Working notes, TODOs, findings, implementation plans, bug-fix notes, and per-release notes live under the gitignored **`.dev/`** directory. Durable internal product, architecture, design, integration, and distribution decisions live under **`dev_docs/`**. A deliberately small set of stable decisions for outside readers lives under **`docs/`**, with no docs site, navigation framework, or marketing layer.

Browse internal durable decisions from [dev_docs/README.md](dev_docs/README.md).

```text
dev_docs/
  README.md          # catalog
  assets/            # referenced images only
  product/           # product direction, architecture, ADRs
  design/            # durable visual language
  integrate/         # external contracts
  ship/              # distribution constraints
```

**No public docs site / no GitHub Pages landing.** Repo face remains README + Releases; `docs/` only publishes the few stable decisions that outside readers need.

Rules:

- **Working notes → `.dev/`.** This includes feature specs, bug-fix notes, implementation plans, TODOs, findings, and per-release notes. `.dev/` is gitignored.
- **Durable internal decisions → `dev_docs/`.** Record only stable product, architecture, design, integration, or distribution decisions; update the catalog.
- **Stable external decisions → `docs/`.** Keep this set small. Do not add site scaffolding, navigation, themes, a wiki, or marketing pages.
- **One language per doc** — no EN/ZH duplicate pairs.
- **Assets stay in `dev_docs/assets/`** (README images included).
- Code, tests, issues, and GitHub Releases remain the source of truth for implemented behavior and version changes.
- **Tests:** Prefer automating anything deterministic and cheap (`swift test`). Humans do a short UX smoke after green — not instead of unit tests during development.
- `AGENTS.md` (this file) stays at repo root so agents always see direction.

## Code signing

- Local builds must use ad-hoc signing (`codesign --sign -`) and remain fully non-interactive.
- Build scripts must never discover, create, unlock, or add a signing keychain to the user's keychain search list.
- Developer ID signing is allowed only when `KAJI_CODESIGN_IDENTITY` is supplied explicitly by CI or a release operator. Missing configuration must fall back to ad-hoc signing, never a password prompt.

## Code touch rules (when implementing lean modules)

Start incremental — no multi-target rewrite:

1. `Prefs.enabledModules`
2. Filter popover pages to enabled modules
3. Slim defaults (System/Goals off; heavy Break off)
4. Composable status-item slots (quota + optional work countdown)
5. Disabled module ⇒ stop its timers/polls

Primary files today: `Sources/Kaji/{AppDelegate,Prefs,KajiPopoverView,StatusItemView,SettingsView}.swift`.

## Popover layout rules (learned from repeat regressions)

1. **No hard-coded chrome heights.** `NSPopover.contentSize` is clamped to
   `maxContentHeight` while the hosting view keeps its full SwiftUI height, so
   any overshoot renders as a blank strip above the header — and only once a
   list is long enough to hit the scroll cap, which is why short pages look
   fine. The scroll budget must be derived from a measured chrome height
   (`PopoverHeightBudget` + `PanelScrollHeightKey`), never from a constant.
   Any change to the header, footer, dividers, stack spacing or outer padding
   must keep `PopoverHeightBudgetTests` green.
2. **Never nest a second `NSPopover` inside the status-item popover.** A text
   field in a child popover resigns first responder in a window with no
   successor, throwing `NSInternalInconsistencyException` from
   `-[NSWindow _newFirstResponderAfterResigning]` during layout — the app
   hangs or dies. Secondary surfaces (notes, details) belong in the parent
   window as anchored overlays (`anchorPreference` +
   `overlayPreferenceValue`).
3. **Hover disclosure needs an explicit dismissal state machine.** An
   in-window card has no system dismissal: pointer-out of trigger, pointer-out
   of card, focus loss, page switch and horizon switch must all funnel through
   one policy (`NoteCardHoverPolicy`), with an active edit as the only veto.
   Timing comes from `HoverDisclosurePolicy`, not per-call-site constants.

## Non-goals (explicit)

- Ice-style management of other status items
- Downloadable third-party plugins / signing sandbox
- Turning Pet into a fifth menu-bar hero (keep `pet-state.json` bridge)
- Shipping “platform” vibes before users can turn off drama

## Design

- One visual language only: **黑白灰 Mono** light/dark. See [dev_docs/design/design-language.md](dev_docs/design/design-language.md).
- Do not reintroduce Calm blue or Playful/green product themes. Settings Color toggle is debt to remove when coding starts.
