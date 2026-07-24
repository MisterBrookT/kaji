# AGENTS.md

Guidance for humans and coding agents working on Kaji.

## What Kaji is

Kaji is a **truncatable macOS menu-bar module host**.

- Default should feel **small and quiet** (quota rings first).
- Extra capabilities (work/break, system, goals, heavy break theater) are **opt-in modules**, not a forced bundle.
- “All-in-one” means **one shell, assemble what you want** — not install-once-get-everything.

Canonical product drafts (not shipped yet):

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
5. Do **not** bump version / cut a GitHub Release until lean-default is validated on a side branch.

## Current branch policy

- Direction work lives on side trees such as `docs/lean-module-host` / later `feat/*`.
- Do not merge straight into a marketed release on `main` until internal docs + slim defaults feel right.
- WIP feature experiments (heavy break art, etc.) should stay parked (stash/branch) until they fit an opt-in module.

## Internal docs (`dev_docs/`)

All working notes live under **`dev_docs/`** — product, design, integrate, ship, assets, old landing `index.html`.

Browse from [dev_docs/README.md](dev_docs/README.md).

```text
dev_docs/
  README.md          # catalog
  assets/            # images only
  product/           # product direction & architecture drafts
  design/            # visual language & shot guides
  integrate/         # external contracts (pet bridge, …)
  ship/              # distribution / release ops
  index.html         # old marketing page (parked; not a public docs site)
```

Rules:

- **Do not use `docs/` as a public documentation site right now.** Public docs are deferred; write them later only if needed.
- **One language per doc** — no EN/ZH duplicate pairs.
- **Assets stay in `dev_docs/assets/`.**
- New internal prose goes in the matching category folder; update the catalog.
- After product direction is reviewed: write an **acceptable feature spec** under `dev_docs/specs/`.
- **Plan docs are optional.** Use them when the work spans many files/sessions or another agent has zero context. If the spec already has clear acceptance cases and a small file touch list, go **tests → implement** and skip a separate plan.
- **Tests:** Prefer automating anything deterministic and cheap (`swift test`). Humans do a short UX smoke after green — not instead of unit tests during development.
- Keep specs in `dev_docs/specs/` (repo truth for humans + agents). Do **not** put product specs under `.cursor/` (IDE chrome; easy to ignore or not share).
- `AGENTS.md` (this file) stays at repo root so agents always see direction.

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
