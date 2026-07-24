# Architecture sketch: lean modules (no ship)

> Companion to [lean-module-host.md](./lean-module-host.md)  
> Branch: `docs/lean-module-host` · draft · **do not release from this note alone**

## Current shape (today)

```text
AppDelegate
  ├─ QuotaStore          (always polled)
  ├─ WorkSessionController
  ├─ SystemMonitor
  ├─ DailyGoalStore
  ├─ NSStatusItem → StatusItemView   (quota rings only)
  └─ NSPopover → KajiPopoverView     (hard-coded KajiPanel: quota|work|system|goals)
```

Everything is always constructed; the carousel always exposes four panels. That is the structural reason “加戏” cannot be escaped without rolling back the app.

## Target shape (incremental)

```text
AppDelegate
  ├─ ModuleRegistry                 (ids, default-on, factories)
  ├─ Prefs.enabledModules           (Set<KajiModuleID>)
  ├─ controllers created / started only if enabled
  ├─ NSStatusItem → StatusItemView  (HStack of module status slots)
  └─ NSPopover → KajiPopoverView    (pages = enabled modules only)
```

No XPC, no dynamic `.bundle` loading, no store in v1. “Plugin” language in product docs means **opt-in first-party module**, not downloadable code.

## Minimal types (proposed)

```swift
enum KajiModuleID: String, CaseIterable, Codable {
    case quota, work, system, goals
}

struct ModuleStatusSlot: Identifiable {
    var id: KajiModuleID
    // SwiftUI view built by the module for the menu bar strip
}

// Prefs
var enabledModules: Set<KajiModuleID>  // persist as [String]
```

Popover: replace `KajiPanel.allCases` with `prefs.enabledModules.sorted(by: stableOrder)`.

Status item: compose slots from enabled modules that opt into `statusSlot` (quota always when enabled; work when enabled and phase warrants a countdown).

## Lifecycle rules

| Module disabled | Effect |
| --- | --- |
| `quota` | stop `QuotaStore` timer / script; no rings |
| `work` | stop session timer; dismiss overlay; no work panel / countdown |
| `system` | stop `SystemMonitor` polling |
| `goals` | keep store cheap or lazy-load; hide panel |

At least one module should remain enabled (prefer forcing `quota` on, or “last module cannot disable” — decide in implementation).

## File touch list (when coding starts)

| Area | Files |
| --- | --- |
| Prefs + L10n | `Prefs.swift`, `SettingsView.swift` |
| Popover filter | `KajiPopoverView.swift` |
| Status compose | `StatusItemView.swift`, `AppDelegate.swift` |
| Gating polls | `QuotaStore.swift`, `SystemMonitor.swift`, `WorkSessionController.swift` |

Do **not** require splitting `Package.swift` into multiple targets for the first cut.

## KajiCore（可测纯逻辑）

`Sources/KajiCore` 放 **无 AppKit/SwiftUI 依赖** 的纯逻辑，供 `swift test` 覆盖。今日：`ModulePrefsLogic`（模块归一化 / popover 页序）。后续 work 状态栏槽的 slot model（`workEnabled + phase + clocks → 文案?`）也可落在此层；UI（`StatusItemView`）只消费模型。

## Explicitly out of tree

- Ice / hiding third-party `NSStatusItem`s
- Remote module download, code signing of plugins
- Rewriting Break/Quota UI while introducing the boundary (boundary first, drama deletion second)

## Definition of done for “try locally, still no release”

- Fresh defaults feel closer to early “small” Kaji (quota-forward).
- A user who hates Work/System/Goals can disable them and never see them in the carousel.
- Heavy break path is not the default surprise.
- `main` Release / version marketing unchanged until this is validated.
