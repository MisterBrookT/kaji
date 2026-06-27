<div align="center">

# Kaji

**A beautiful macOS menu bar for AI usage.**

Local-first quota rings for Claude, Codex, MiniMax, and Ark Agent.

[中文](README.zh.md)

<a href="https://github.com/interesting-vibe-coding/kaji/releases/latest"><img src="https://img.shields.io/github/v/release/interesting-vibe-coding/kaji?color=F25C05&label=release&labelColor=211C15" alt="latest release"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-F25C05?labelColor=211C15" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/interesting-vibe-coding/kaji?color=F25C05&labelColor=211C15" alt="MIT license"></a>

<br>
<br>

<img src="docs/menubar-light.png" width="598" alt="Kaji menu bar rings">

<br>
<br>

<img src="docs/gauge-light.png" width="520" alt="Kaji quota popover">

</div>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/interesting-vibe-coding/kaji/main/install.sh | bash
```

Requires macOS 13+ on Apple Silicon. The installer downloads the latest release,
moves Kaji into `/Applications`, and launches the menu bar app.

> Kaji is currently unsigned. The installer clears the Gatekeeper quarantine flag
> transparently; this goes away after signing and notarization.

## What It Shows

- **Menu bar rings** - compact dual-ring status for the providers you choose to show.
- **Quota popover** - 5h usage, 7d usage, local reset time, provider toggles, S/M/L size, used/remaining mode, and EN/CN language.
- **Provider coverage** - Claude, Codex, MiniMax, and Ark Agent.
- **Quiet styling** - native menu bar behavior, light/dark themes, mono or color mode.
- **Update hint** - a small dot appears when a newer GitHub Release is available.

## How It Works

```text
local CLI/account data -> bundled quota.py reader -> SwiftUI menu bar + popover
```

Kaji reads local quota/account windows through a bundled Python reader, then
renders the result in a native SwiftUI menu bar surface. Nothing is uploaded.

Network use is intentionally narrow:

- GitHub Releases for update checks.
- Volcengine/Ark endpoints only when Ark Agent credentials are configured.

## Build from Source

```sh
swift run                 # development menu bar app
./scripts/build-app.sh    # release bundle -> dist/KajiGauge.app
```

On CLT-only machines where SwiftPM linking fails, use:

```sh
./scripts/build-local.sh  # raw swiftc build, installs to /Applications
```

## Limitations

Kaji is a local status app, not a billing source of truth. Provider APIs and
local file formats can change; unavailable windows render as empty or unknown
until the reader can see usable data again.

## License

MIT - see [LICENSE](LICENSE).
