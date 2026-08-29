<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**The personal status and control layer for an AI-native Mac.**

What matters today, one glance away.

[中文](README.zh.md) · [Português](README.pt-BR.md) · [Español](README.es.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

</div>

https://github.com/user-attachments/assets/a345bc3f-d74e-4092-8e8f-5730b154d39c

## What it is

Kaji brings the live state that matters to you into the **Menu Bar**. This includes AI quota, focus, goals, and your Mac.

Why the Menu Bar? It stays beside whatever you are doing: glance to know, hover for context, click to act. No app switch and no notification demanding attention.

Kaji starts small. Quota is on. Other modules are opt-in. One shell. Only the signals you choose to keep close.

`Kaji` is Japanese `舵 / かじ`. It means rudder.

[Read the product principles](docs/product-principles.md).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

Needs macOS 13+ (Apple Silicon), `git`, and `swift`. Clones the latest release tag, builds locally, clears quarantine, installs to `/Applications`.

No `.app.zip` on Releases (unsigned browser downloads trip Gatekeeper). Or run `./scripts/build-local.sh` from a clone.

## Modules

| Module | Default | What you get |
| --- | --- | --- |
| **Quota** | on | 5h / 7d usage, reset timing, providers |
| **Work / Break** | off | Focus timer, menu-bar countdown, break overlay |
| **System** | off | CPU / memory, disk categories, top processes |
| **Goals** | off | Today / Week / Vision / Schedule, notes, tags, heatmap |

Theme: **Mono** only (black / white / gray, light & dark).

## Build

```sh
swift test
./scripts/build-local.sh
```

### UI tests

Two layers, split by what each can actually prove:

- **In-process** — `Tests/KajiTests/PopoverInteractionTests.swift` + `PopoverRenderTests.swift`, run by plain `swift test` (no XCUITest target; SwiftPM can't host one — see `Tests/KajiTests/UITestHarness.swift`). These boot the real `AppDelegate`/status-item/popover object graph in-process and invoke the real click-handler closure `setupStatusItem()` wires up, so a regression in that wiring, or in `showPopover`'s state/content, fails for real. They do **not** cover real OS-level click delivery — a synthetic click reliably does not reach a SwiftUI `Button`'s gesture recognizer from inside a bare `xctest` process, and some activation-state-dependent bugs (e.g. a window that hides itself because clicking the status item never activates an `LSUIElement` app) only manifest with a real OS click against a real, launched, frontmost `.app` — this layer cannot see those. `PopoverRenderTests` writes one PNG per module page to `.build/ui-snapshots/` for visual inspection.
- **Real click, real .app** — `scripts/ui-smoke.sh` launches the actual signed `Kaji.app`, posts a genuine `CGEvent` click at the status item, and asserts on `CGWindowList`. This is the only layer that proves a real click actually opens the popover on screen.

## Links

- [Latest release](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md): contributor / agent notes
- [Published decisions](docs/product-principles.md): product, modules, design, and integration boundaries
- [dev_docs/](dev_docs/README.md): internal durable decisions

## License

MIT. See [LICENSE](LICENSE).
