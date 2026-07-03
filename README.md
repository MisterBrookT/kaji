<div align="center">

# Kaji

**A beautiful macOS menu bar for AI coding usage.**

Kaji reads quota windows from multiple AI coding vendors and puts them in a
quiet macOS menu bar signal.

Kaji keeps your coding-agent quota visible before a long prompt hits a wall. It
is local-first, native, and small enough to live beside Wi-Fi and battery.

Kaji 会在长任务撞上额度墙之前提醒你。它本地优先、原生、轻，适合一直待在菜单栏里。

[中文](README.zh.md)

<a href="https://github.com/MisterBrookT/kaji/releases/latest"><img src="https://img.shields.io/github/v/release/MisterBrookT/kaji?color=5C86A3&label=release&labelColor=1A1A1A" alt="latest release"></a>
<a href="https://github.com/MisterBrookT/kaji/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/MisterBrookT/kaji/ci.yml?branch=main&label=build&labelColor=1A1A1A&color=5C86A3" alt="build status"></a>
<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=5C86A3" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-5C86A3?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=5C86A3&labelColor=1A1A1A" alt="MIT license"></a>

<br>
<br>

<p align="center"><img src="docs/hero.png" width="820" alt="Kaji macOS menu bar quota app"></p>

</div>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Requires macOS 13+ on Apple Silicon. The installer downloads the latest release,
moves Kaji into `/Applications`, stops old copies, and launches the menu bar app.

> Kaji is currently unsigned. The installer clears the Gatekeeper quarantine flag
> transparently; this goes away after signing and notarization.

## Why Kaji

Coding agents are useful until their quota disappears mid-run. Kaji turns quota
windows into a quiet menu bar signal: glance once, keep working.

## What It Shows

- **Menu bar rings**: compact dual-ring status for selected providers.
- **Quota popover**: 5h usage, 7d usage, local reset time, provider toggles, refresh, updates, Keep Awake, and Xiaochai.
- **Settings window**: slower preferences such as visual style, used/remaining mode, S/M size, and EN/CN language.
- **Quiet native surface**: no dashboard, no dock icon, no floating panel.
- **Keep Awake**: optional macOS sleep-disable control for long agent runs and clamshell setups.
- **Pet launcher**: start or stop the selected PetHatch pet from the Kaji popover when PetHatch is available locally.
- **Three visual modes**: Mono is the default; Calm adds blue-gray accents; Playful adds warmer orange accents.
- **One-click updates**: a small dot appears when a newer GitHub Release is available; open Kaji and choose `Update to vX`.
- **Pet bridge**: local `pet-state.json` for desktop-pet runtimes. See [docs/pet-bridge.md](docs/pet-bridge.md).

## Supported Providers

Kaji currently supports four AI coding vendors. Vendor-specific adapters stay
local-first and only read the account or CLI data that already exists on your
machine.

| Scope | What Kaji Tracks |
| --- | --- |
| Local vendor adapters | Local quota and usage windows |
| CLI-backed adapters | Token-plan usage through local developer tools |
| Credential-backed adapters | Optional remote quota windows when local credentials exist |

## How It Works

```text
local CLI/account data -> bundled quota.py reader -> SwiftUI menu bar + popover
```

- **Local reader**: a bundled Python script reads local quota/account windows.
- **Native surface**: SwiftUI renders the menu bar rings and popover.
- **Narrow network use**: GitHub Releases for update checks; optional provider
  endpoints are contacted only when their local credentials are configured.
- **Explicit system control**: Keep Awake uses macOS `pmset disablesleep` and asks for administrator approval when toggled.

Nothing is uploaded.

## Pet Bridge

Kaji writes a local state file at:

```text
~/Library/Application Support/Kaji/pet-state.json
```

Desktop-pet runtimes can map it to `idle`, `running`, `review`, `waiting`, or
`failed` animation. Kaji stays the quota/status layer; `hatch-pet` stays the pet
asset compiler.

Kaji can also launch the local PetHatch Xiaochai runtime from the popover. It
checks `KAJI_PETHATCH_ROOT`, `defaults write dev.kaji petHatchRoot /path/to/pethatch`,
then common developer paths such as `~/workspace/pethatch`. The Settings window
can choose between known PetHatch pets such as Xiaochai and Openclaw. Packaged
runtime discovery can move there later. When launched this way, Kaji passes the
same `pet-state.json` to PetHatch so the pet can react to quota pressure instead
of running as a standalone timer only.

## Build from Source

```sh
swift run                 # development menu bar app
./scripts/build-app.sh    # release bundle -> dist/Kaji.app
```

On CLT-only machines where SwiftPM linking fails, use:

```sh
./scripts/build-local.sh  # raw swiftc build, installs to /Applications
```

## FAQ

**Why does macOS warn that Kaji is unsigned?**

Kaji is not signed or notarized yet. The installer removes the quarantine flag and says so explicitly.

**Where does optional provider configuration live?**

Use `~/.config/kaji/volcengine.env` for the optional remote adapter. Legacy
`~/.config/kaji-gauge/volcengine.env` still works as a fallback.

**Does Kaji replace provider billing dashboards?**

No. Kaji is a local status mirror, not a billing source of truth.

## Limitations

Provider APIs and local file formats can change. When Kaji cannot read a usable
window, the matching provider renders as empty or unknown until data is visible
again.

## License

MIT - see [LICENSE](LICENSE).
