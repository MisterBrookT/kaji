<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**The menu bar worth keeping for AI coding.**

See how much quota is left. Add the rest only if you want it.

[中文](README.zh.md)

<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

<img src="dev_docs/assets/use-quota.png" width="560" alt="Kaji quota popover: Claude Code, Codex and Cursor, each with its two usage windows, percentage and reset time" />

</div>

## What it is

Claude Code and Codex meter you on rolling windows. Kaji puts the answer in the menu bar: how much is used, and when it resets.

Each provider shows both of its windows — the short session window and the long one — with a percentage and the reset time. Nothing to open, nothing to ask.

Quota is on by default. Work timer and goals are modules you turn on if you want them. `Kaji` is Japanese `舵 / かじ` — rudder.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

macOS 13+ (Apple Silicon), plus `git`, `swift` and `python3`. The installer builds from the latest release tag and installs to `/Applications`.

There is no prebuilt download: Kaji has no Developer ID signature yet, and an unsigned `.app.zip` from a browser is blocked by Gatekeeper. Building locally is the honest path. From a clone: `./scripts/build-local.sh`.

Trouble, or want it gone? [FAQ & troubleshooting](docs/faq.md).

## Modules

| Module | Default | What you get |
| --- | --- | --- |
| **Quota** | on | Usage and reset time per window, per provider |
| **Work / Break** | off | Focus timer, menu-bar countdown, break overlay |
| **Goals** | off | Today / Week / Vision, tags, notes, `kaji` CLI |

Turning a module off removes its page *and* stops its timers and polling. One theme: black, white, gray — light and dark.

<details>
<summary>Work timer and goals</summary>

<br>

A countdown you can read without opening anything, and a break that actually interrupts.

<img src="dev_docs/assets/use-work.png" width="480" alt="Work panel: 07:57 remaining, 45m focus and 2m break, with start, skip and reset" />

Today / Week / Vision goals, with a `kaji` CLI so an agent can add and close them for you.

<img src="dev_docs/assets/use-goals.png" width="480" alt="Goals panel: today's goals grouped by tag with completion dots" />

</details>

## Privacy

Kaji reads the files your AI tools already write, and for providers that only publish quota server-side, calls that provider's usage endpoint with the credentials already on your Mac.

- **Read locally:** `~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/rollout-*.jsonl`, and the local credential stores when a provider needs them.
- **Leaves your Mac:** a usage request to `api.anthropic.com` or `api2.cursor.sh` with *your* token, and a version check against `api.github.com`. Only for providers you enable.
- **No analytics, no account, no server of ours.** Prompts, usage and goals are never sent anywhere. The CLI talks to the app over `127.0.0.1` only.

How each number is computed: [how quota works](docs/quota.md).

## Docs

- [How quota works](docs/quota.md) · [FAQ](docs/faq.md) · [CLI reference](docs/cli.md)
- [Product principles](docs/product-principles.md) · [module architecture](docs/module-architecture.md) · [design language](docs/design-language.md)
- [AGENTS.md](AGENTS.md) — contributor and agent notes

## Contributing

Issues and PRs welcome. Run `swift test` first; layout invariants and UI-test layering are in [AGENTS.md](AGENTS.md).

## License

MIT. See [LICENSE](LICENSE).

Not affiliated with Anthropic, OpenAI, Anysphere, or any other provider. Product names and marks belong to their owners.
