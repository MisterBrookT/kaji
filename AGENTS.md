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

- [dev_docs/product/lean-module-host.md](dev_docs/product/lean-module-host.md)
- [dev_docs/product/architecture-modules.md](dev_docs/product/architecture-modules.md)

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

## Internal docs (`dev_docs/`)

All working notes live under **`dev_docs/`** — product, design, integrate, ship, assets.

Browse from [dev_docs/README.md](dev_docs/README.md).

```text
dev_docs/
  README.md          # catalog
  assets/            # referenced images only
  product/           # product direction, architecture, ADRs
  design/            # durable visual language
  integrate/         # external contracts
  ship/              # distribution constraints
```

**No public docs site / no GitHub Pages landing.** Repo face is README + Releases only — less is more for a menu-bar tool.

Rules:

- **Internal prose → `dev_docs/`.** Do not recreate a `docs/` wiki or marketing site.
- **One language per doc** — no EN/ZH duplicate pairs.
- **Assets stay in `dev_docs/assets/`** (README images included).
- New internal prose must record a durable product, architecture, design, integration, or distribution decision; update the catalog.
- Do **not** archive feature specs, bug-fix notes, implementation plans, or per-release notes in `dev_docs/`; code, tests, issues, and GitHub Releases are their source of truth.
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

## Non-goals (explicit)

- Ice-style management of other status items
- Downloadable third-party plugins / signing sandbox
- Turning Pet into a fifth menu-bar hero (keep `pet-state.json` bridge)
- Shipping “platform” vibes before users can turn off drama

## Design

- One visual language only: **黑白灰 Mono** light/dark. See [dev_docs/design/design-language.md](dev_docs/design/design-language.md).
- Do not reintroduce Calm blue or Playful/green product themes. Settings Color toggle is debt to remove when coding starts.
