# Product principles

Kaji is a truncatable macOS menu-bar module host. Its job is to keep a small set of changing, useful signals close to the user without turning the menu bar into another dashboard.

## Quiet by default

The default experience starts with the quota module. Other capabilities are opt-in. A module that is disabled should leave both the interface and its background work.

The standard for adding a capability is whether its state changes during the day, can be understood at a glance, occasionally needs an immediate action, and would be unnecessarily heavy as a separate app. Available space alone is not a reason to add it.

"Worth keeping" does not mean "kitchen sink." Modularity exists so Kaji can become smaller for each user, not so every possible feature can accumulate in one installation.

## Explicit non-goals

Kaji does not manage or hide other applications' status items in the style of Ice or Bartender. It also does not provide a marketplace for downloadable third-party plugins. Both would add substantial product and trust surfaces that do not serve the current goal.

Kaji uses one shell with opt-in first-party modules. New modules must justify their place near the user's current work and remain removable.

Related decisions: [module architecture](module-architecture.md), [design language](design-language.md), and [CLI integration](cli-integration.md).
