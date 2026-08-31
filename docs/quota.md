# How quota works

Kaji does not have an account, a backend, or a scraper. Every number in the Quota panel comes from one of two places on your own Mac: files your AI coding tools already write, or the provider's own usage endpoint called with the credentials that tool already stored locally.

A bundled Python reader (`Resources/quota.py`, shipped inside `Kaji.app`) produces the JSON the app renders. It runs every 30 seconds. This is why Kaji needs a working `python3`.

## Per provider

| Provider | 5h / 7d windows | Token and cost numbers |
| --- | --- | --- |
| **Claude Code** | `https://api.anthropic.com/api/oauth/usage`, authorized with the OAuth token in `~/.claude/.credentials.json`. Cached for 1 hour. | Local parse of `~/.claude/projects/**/*.jsonl` (`message.usage`) — the same fields `ccusage` reads. |
| **Codex** | The local `codex` CLI, via `codex app-server` → `account/rateLimits/read`. No direct network call from Kaji. Cached for 3 minutes. | Local parse of `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` `token_count` events. Values are session-cumulative, so the last event per file wins. |
| **Cursor** (opt-in) | `api2.cursor.sh` dashboard usage, authorized with the access token in Cursor's `state.vscdb`. This is a monthly billing pool, mapped onto the 5h / 7d slots (outer = API, inner = Auto), not a real session window. | Not exposed. |
| **MiniMax, Ark Agent** (opt-in) | Provider OpenAPI, only when you have configured that provider's key locally. | Provider-reported. |

Only providers you enable are queried. `—` means "no data for this window", not zero.

Windows and caches are stored under `~/.helm/sessions/`.

## Accuracy caveats

- Claude and Codex percentages are the provider's own numbers, so they match what `/usage` or the Codex TUI reports — subject to the cache TTL above.
- Token and cost figures are computed from local session logs and are estimates. They are useful for "how heavy was today", not for reconciling a bill.
- Cursor's percentages describe a billing period, not a rolling session; treat the ring as budget burn, not a reset countdown.
- If a provider changes its endpoint or log format, that provider's row degrades to `—` rather than showing a wrong number.

## What leaves your Mac

- A usage request to `api.anthropic.com` (Claude enabled) and `api2.cursor.sh` (Cursor enabled), carrying only your own provider token.
- A version check against `api.github.com/repos/MisterBrookT/kaji/releases/latest`.

That is the complete list. There is no analytics, no crash reporting, no Kaji-operated server, and no transmission of prompts, file contents, goals, or usage data anywhere else. The `kaji` CLI reaches the app over `127.0.0.1` only.

## Why read credential files at all

For Claude and Cursor there is no local file that contains the account's remaining quota — only the provider knows it. Kaji reuses the token the official tool already wrote to disk so you never paste a key into Kaji. If you would rather Kaji never touch those files, disable that provider: the code path is not entered for a disabled provider.
