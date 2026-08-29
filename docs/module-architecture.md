# Module architecture

Kaji is one application shell composed of first-party modules. The shell owns shared lifecycle and presentation concerns. Each module owns a distinct signal or control surface.

Current module identifiers include Quota, Work, System, Goals, and Mail Brief. Quota is the small default experience. Optional modules are enabled through preferences and appear only when selected.

## Why capabilities are opt-in

Menu-bar software stays visible for long periods. A capability that is useful to one person can become persistent noise for another. Opt-in capabilities let the application retain a coherent shell while each installation stays small.

The boundary is behavioral as well as visual. Disabling a module should remove its popover page and status-item contribution, stop its timers or polling, and dismiss module-owned transient UI. A hidden page with an active background worker is not a disabled module.

## Deliberately limited extensibility

"Module" currently means an in-tree, first-party capability. Kaji does not load remote bundles or third-party executable plugins. This avoids a plugin distribution, compatibility, signing, permission, and support system before there is evidence that such a system is needed.

The architecture should remain incremental. Shared code belongs in the shell or testable core logic only when multiple modules genuinely need it. Module boundaries are a way to preserve lifecycle control and truncatability, not a reason to rewrite the application into a framework.
