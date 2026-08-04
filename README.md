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

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260724.jpg" width="860" alt="Kaji menu bar popover" />

</div>

## What it is

Kaji brings the live state that matters to you into the **Menu Bar**. This includes AI quota, focus, goals, and your Mac.

Why the Menu Bar? It stays beside whatever you are doing: glance to know, hover for context, click to act. No app switch and no notification demanding attention.

Kaji starts small. Quota is on. Other modules are opt-in. One shell. Only the signals you choose to keep close.

`Kaji` is Japanese `舵 / かじ`. It means rudder.

[Read the vision](dev_docs/product/vision.md).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

Needs macOS 13+ (Apple Silicon), `git`, and `swift`. Clones the latest release tag, builds locally, clears quarantine, installs to `/Applications`.

No `.app.zip` on Releases (unsigned browser downloads trip Gatekeeper). Or run `./scripts/build-local.sh` from a clone.

## Modules

| Module | Default | What you get |
| --- | --- | --- |
| **Quota** | on | 5h / 7d usage, reset, token trend, cost estimate, providers |
| **Work / Break** | off | Focus timer, menu-bar countdown, break overlay |
| **System** | off | CPU / memory / disk, top processes, conservative Auto Reclaim |
| **Goals** | off | Daily goals + heatmap |
| **Pet** | bridge | Optional Navi via `~/Library/Application Support/Kaji/pet-state.json` |

Theme: **Mono** only (black / white / gray, light & dark).

## Build

```sh
swift test
./scripts/build-local.sh
```

## Links

- [Latest release](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md): contributor / agent notes
- [dev_docs/](dev_docs/README.md): internal specs

## License

MIT. See [LICENSE](LICENSE).
