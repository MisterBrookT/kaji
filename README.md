<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**The menu bar worth keeping for AI coding.**

Quota rings at a glance. Assemble the rest only when you need it.

[中文](README.zh.md)

<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

<img src="dev_docs/assets/use-quota.png" width="620" alt="Kaji in the menu bar: Claude Code and Codex quota with 5h and 7d windows" />

</div>

## What it is

Kaji keeps the live state that matters to you in the **menu bar**: how much Claude Code and Codex quota is left, whether you are in a focus block, what you said you would do today.

Why the menu bar? It stays beside whatever you are doing — glance to know, hover for context, click to act. No app switch, no notification demanding attention.

Kaji starts small. Quota is on; everything else is opt-in. `Kaji` is Japanese `舵 / かじ` — rudder.

## Three things people actually use it for

**1. Know how much AI quota is left, without asking.** 5h session window and 7d window per provider, with time to reset — shown above. The rings live in the menu bar; the numbers are one click away.

**2. Work in focus blocks instead of drifting.** A countdown you can read from the menu bar, and a break that actually interrupts you.

<img src="dev_docs/assets/use-work.png" width="560" alt="Work panel: 07:57 remaining, 45m focus / 2m break, start break and reset controls" />

**3. Keep today's goals where you can't ignore them.** Today / Week / Vision horizons, tags, notes — and a `kaji` CLI so your agent can add and close goals for you.

<img src="dev_docs/assets/use-goals.png" width="560" alt="Goals panel: today's goals grouped by tag with completion dots" />

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Needs macOS 13+ (Apple Silicon), `git`, `swift` (Xcode or the Swift toolchain), and a working `python3`. The installer clones the latest release tag, builds locally, installs to `/Applications`, clears quarantine, and launches.

Kaji ships no prebuilt `.app.zip`: it is not yet signed with a Developer ID, and unsigned browser downloads trip Gatekeeper. Building from source is currently the honest path. From a clone: `./scripts/build-local.sh`.

Something went wrong, or you want it gone? [FAQ & troubleshooting](docs/faq.md).

## Modules

| Module | Default | What you get |
| --- | --- | --- |
| **Quota** | on | 5h / 7d usage, reset timing, per-provider rings |
| **Work / Break** | off | Focus timer, menu-bar countdown, break overlay |
| **System** | off | CPU / memory, disk categories, top processes |
| **Goals** | off | Today / Week / Vision / Schedule, notes, tags, heatmap |

Disabling a module removes its page *and* stops its timers and polling. Theme: **Mono** only (black / white / gray, light & dark).

## Privacy

Kaji reads local files that AI coding tools already write on your Mac, and — for providers that only publish quota server-side — calls that provider's own usage endpoint with the credentials already stored on your machine.

- **Read locally:** `~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/rollout-*.jsonl`, and, when the provider needs it, the local credential stores (`~/.claude/.credentials.json`, Cursor's `state.vscdb`).
- **Leaves your Mac:** a usage request to `api.anthropic.com` (Claude) and `api2.cursor.sh` (Cursor) using *your* token, plus a version check against `api.github.com`. Nothing else, and only for providers you enable.
- **No analytics, no account, no server of ours.** Your usage data, prompts, and goals are never sent anywhere. Goals stay in local storage; the CLI talks to the app over `127.0.0.1` only.

Details, including exactly how each number is computed: [how quota works](docs/quota.md).

## Docs

- [How quota works](docs/quota.md) — sources, accuracy, providers, privacy
- [FAQ & troubleshooting](docs/faq.md) — python3 errors, blank quota, uninstall
- [CLI reference](docs/cli.md) — drive goals from a shell or an agent
- [Product principles](docs/product-principles.md) · [module architecture](docs/module-architecture.md) · [design language](docs/design-language.md)
- [AGENTS.md](AGENTS.md) — contributor and agent notes
- [Latest release](https://github.com/MisterBrookT/kaji/releases/latest)

## Contributing

Issues and PRs welcome. Run `swift test` before opening a PR; UI-test layering and layout invariants are documented in [AGENTS.md](AGENTS.md).

## License

MIT. See [LICENSE](LICENSE).

Not affiliated with Anthropic, OpenAI, Anysphere, or any other provider. Product names and marks belong to their owners.
