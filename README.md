<div align="center">

<h1>
  <img src="https://cdn.jsdelivr.net/gh/MisterBrookT/kaji@main/docs/readme-panda.png" height="56" alt="Navi Panda" />
  <br />
  Kaji
</h1>

**A macOS menu bar command center for AI coding.**

Track Claude Code / Codex usage, watch token pressure, keep your Mac awake, manage focus breaks, and let Navi Panda block you when it is time to rest.

[中文](README.zh.md)

<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=5C86A3" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-5C86A3?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=5C86A3&labelColor=1A1A1A" alt="MIT license"></a>

<br />
<br />

<img src="docs/readme-hero-20260708.jpg" width="860" alt="Kaji menu bar popover" />

</div>

## Why

AI coding agents are useful until quota, context, focus, or system pressure breaks the run. Kaji turns those hidden limits into one quiet menu bar surface.

No dashboard. No dock icon. One glance, then back to work.

## Name

`Kaji` comes from Japanese `舵 / かじ`: rudder, helm, the thing that keeps a ship on course. This app does the same for AI coding runs.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Requires macOS 13+ on Apple Silicon. Kaji is currently unsigned; the installer removes quarantine and installs the current build to `/Applications`.

If a direct browser download says the app is damaged, use the install command above. See [Distribution](docs/distribution.md).

## What Kaji Does

| Surface | What you get |
| --- | --- |
| **Quota** | 5h / 7d usage, reset timing, token trend, estimated cost, provider toggles |
| **Work / Break** | Focus timer, break timer, skip count, hard full-screen break overlay |
| **System** | CPU, memory, disk, top processes, one-click Auto Reclaim |
| **Goals** | Editable daily goals, reset, completion heatmap |
| **Pet** | Navi Panda, quota-aware 9-state animation, no message noise |
| **Keep Awake** | Optional macOS sleep prevention for long agent runs |

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
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=MisterBrookT/kaji&type=date&theme=dark&legend=top-left&sealed_token=ZmO2Jj6FA5ouWNGRqovmRT41QyYoBEKIF2xcWsOdFEoGTcfeRr4E7er0aGH6HQnt6a-zbSvwug2vVgtKvXLYnGkPdcD7k32Frid_Q6bzn-PqGYmrAJMPiQe3iLyi734sYEFPMyUUsx0GUHJ9owHt4s1m3AaiPVg1ZG1oBhwzaWqdS3zFWYcJCxstA7H7" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=MisterBrookT/kaji&type=date&legend=top-left&sealed_token=ZmO2Jj6FA5ouWNGRqovmRT41QyYoBEKIF2xcWsOdFEoGTcfeRr4E7er0aGH6HQnt6a-zbSvwug2vVgtKvXLYnGkPdcD7k32Frid_Q6bzn-PqGYmrAJMPiQe3iLyi734sYEFPMyUUsx0GUHJ9owHt4s1m3AaiPVg1ZG1oBhwzaWqdS3zFWYcJCxstA7H7" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=MisterBrookT/kaji&type=date&legend=top-left&sealed_token=ZmO2Jj6FA5ouWNGRqovmRT41QyYoBEKIF2xcWsOdFEoGTcfeRr4E7er0aGH6HQnt6a-zbSvwug2vVgtKvXLYnGkPdcD7k32Frid_Q6bzn-PqGYmrAJMPiQe3iLyi734sYEFPMyUUsx0GUHJ9owHt4s1m3AaiPVg1ZG1oBhwzaWqdS3zFWYcJCxstA7H7" />
 </picture>
</a>

## Build

```sh
swift run
./scripts/build-local.sh
```

Use `scripts/build-local.sh` for release-style local app bundles. It assembles `build/Kaji.app`, copies bundled resources, installs to `/Applications`, and can relaunch the app.

## Links

- [Pet bridge](docs/pet-bridge.md)
- [Design language](docs/design-language.md)
- [Distribution](docs/distribution.md)

## License

MIT. See [LICENSE](LICENSE).
