<div align="center">

<h1>
  <img src="dev_docs/assets/readme-panda.png" height="56" alt="Navi Panda" />
  <br />
  Kaji
</h1>

**A truncatable macOS menu bar for AI coding.**

Quota rings by default. Work/break, system, and goals are opt-in modules — assemble what you want, keep the bar quiet.

[中文](README.zh.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=5C86A3" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-5C86A3?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=5C86A3&labelColor=1A1A1A" alt="MIT license"></a>

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260708.jpg" width="860" alt="Kaji menu bar popover" />

</div>

## Why

AI coding agents are useful until quota, context, focus, or system pressure breaks the run. Kaji turns those hidden limits into one quiet menu bar surface.

No dashboard. No dock icon. One glance, then back to work.

## Name

`Kaji` comes from Japanese `舵 / かじ`: rudder, helm, the thing that keeps a ship on course. This app does the same for AI coding runs.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

Requires macOS 13+ on Apple Silicon, plus `git` and `swift`. The installer clones the latest release tag, builds locally, clears quarantine, and installs to `/Applications`.

We do **not** ship a downloadable `.app.zip` (unsigned zip downloads trip Gatekeeper). GitHub’s source archives on the Release page are fine for reading; use the install command or `./scripts/build-local.sh` to run the app.

See [Distribution](dev_docs/ship/distribution.md).

## What Kaji Does

Default install is **Quota only**. Turn modules on in Settings.

| Surface | Default | What you get |
| --- | --- | --- |
| **Quota** | on | 5h / 7d usage, reset timing, token trend, estimated cost, provider toggles |
| **Work / Break** | off | Focus timer, menu-bar countdown, break overlay |
| **System** | off | CPU, memory, disk, top processes, Auto Reclaim |
| **Goals** | off | Editable daily goals, reset, completion heatmap |
| **Pet** | bridge | Navi Panda via `pet-state.json` (no fifth menu-bar hero) |
| **Keep Awake** | setting | Optional macOS sleep prevention for long agent runs |

## Navi Panda

Navi is not a chat widget. It is a small state layer for your coding session:

- `idle`: resting
- `running`: Codex / Claude usage is moving
- `waiting`: quota or input needs attention
- `review`: output is ready
- `failed`: something broke

Kaji writes local state to:

```text
~/Library/Application Support/Kaji/pet-state.json
```

PetHatch consumes this state and renders Navi with a 9-state atlas.

## Auto Reclaim

System cleanup is intentionally conservative:

- reclaim inactive memory when memory pressure is high
- clean selected Kaji / SwiftPM / developer caches when they are large
- terminate only safe Kaji-owned orphan processes

Kaji does not kill arbitrary dev servers.

## Star History

<a href="https://www.star-history.com/?type=date&repos=MisterBrookT%2Fkaji">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=blackblue-labs/kaji&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=blackblue-labs/kaji&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=blackblue-labs/kaji&type=date&legend=top-left" />
 </picture>
</a>

## Build

```sh
swift run
./scripts/build-local.sh
```

Use `scripts/build-local.sh` for release-style local app bundles. It assembles `build/Kaji.app`, copies bundled resources, installs to `/Applications`, and can relaunch the app.

## Links

- [AGENTS.md](AGENTS.md) — contributor / agent direction
- Internal notes: [dev_docs/README.md](dev_docs/README.md)

## License

MIT. See [LICENSE](LICENSE).
