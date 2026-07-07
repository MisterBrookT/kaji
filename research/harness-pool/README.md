# Harness Pool Research

Date: 2026-06-17

Goal: explore whether Kaji Gauge should grow from a local quota indicator into
a harness pool manager for Claude Code, Codex, Gemini CLI, MiniMax/Ark wrappers,
OpenCode, and similar coding-agent surfaces.

This is research only. It does not propose changing the shipped app yet.

Companion planning doc: `PLAN.md`.

## Current Kaji Gauge Position

Kaji Gauge is already close to the "quota cockpit" layer:

- It reads local/session usage for Claude Code, Codex, Kiro, OpenCode.
- It fetches live account windows for Claude and Codex where possible.
- It has MiniMax quota wiring through the `mmx` CLI.
- It intentionally keeps data local; the README says nothing leaves the machine.

Important existing files:

- `Resources/quota.py`: quota collection and provider-specific readers.
- `Sources/KajiGauge/Providers.swift`: provider display metadata.
- `Sources/KajiGauge/QuotaStore.swift`: polling, decoding, and view-ready model.

That makes Kaji Gauge a good base for quota visibility. It is not yet a
request router, account switcher, or provider config manager.

## Projects Reviewed

### Sub2API

Source: <https://github.com/Wei-Shaw/sub2api>

Sub2API is an AI API gateway for distributing subscription quota through
generated API keys. Its README describes:

- multi-account upstream management with OAuth and API-key account types
- generated downstream API keys for users
- token-level usage tracking and billing
- smart scheduling with sticky sessions
- per-user and per-account concurrency controls
- request/token rate limits
- admin dashboard, PostgreSQL, Redis, Docker/systemd deployment

Its release notes also describe account-group scheduling indexes, user filtering
by API-key group, and gateway error handling across Messages, ChatCompletions,
Responses, and platform-specific paths.

Takeaway: Sub2API is a server-side gateway. It solves pooling, quota
distribution, billing, scheduling, and concurrency. It is much heavier than
Kaji Gauge's current local menubar model.

Risk note: Sub2API's README explicitly warns that using it may violate upstream
provider terms and may cause account bans or service interruption. That matters
if we copy the "subscription to API gateway" direction.

### CC Switch

Source: <https://github.com/farion1231/cc-switch>

CC Switch is a Tauri desktop app for managing Claude Code, Claude Desktop,
Codex, Gemini CLI, OpenCode, OpenClaw, and Hermes Agent. Its README positions it
as an all-in-one manager for provider presets and config switching.

Observed capabilities:

- one desktop app for multiple AI CLI tools
- provider presets and one-click switching
- system tray quick switching
- local proxy with hot switching, format conversion, failover, circuit breaker,
  provider health monitoring, and request rectification
- app-level takeover for Claude, Codex, or Gemini providers
- unified MCP, prompts, and skills management
- usage dashboard with spending, requests, tokens, trends, logs, and custom
  per-model pricing
- cloud sync and import/export
- SQLite storage with atomic writes and backups

CC Switch docs also include a Codex OAuth reverse-proxy path that reuses a
ChatGPT account's Codex service inside Claude Code:
<https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/2-providers/2.1-add.md>

That specific feature uses OpenAI's device-code login flow, then routes Claude
provider requests to ChatGPT Codex backend endpoints. The same doc warns about
terms-of-service and account risk.

Takeaway: CC Switch is closest to the "one local control panel for all harnesses"
idea. Its strongest lesson is not just quota display; it owns config files,
provider presets, switch state, logs, and optionally a local proxy.

### cc-account-switcher

Source: <https://github.com/ming86/cc-account-switcher>

Small archived Bash tool for Claude Code account switching.

Observed capabilities:

- add/list/remove Claude Code accounts
- switch by index or email
- macOS Keychain or protected local backup files
- preserves user settings and switches only authentication material
- requires restarting Claude Code after a switch

Takeaway: account switching can be very small if the scope is only "swap auth
state". It does not solve routing, usage accounting, provider abstraction, or
multi-harness config consistency.

### CCS

Source: <https://github.com/kaitranntt/ccs>

CCS advertises switching between Claude accounts, Gemini, Copilot, OpenRouter,
and 300+ models via CLIProxyAPI OAuth proxy, with a visual dashboard and remote
proxy support.

Takeaway: the ecosystem is converging on two shapes:

- config/account switchers for local CLI tools
- API/proxy gateways that normalize many upstreams behind one endpoint

## Design Axes

### Axis 1: Observe vs Control

Observe-only:

- Read usage/quota/session files.
- Display limits, resets, burn rate, and active harnesses.
- No mutation of credentials or config files.
- Lowest risk and strongest fit for current Kaji Gauge.

Control:

- Write provider configs.
- Switch auth/account profiles.
- Manage presets, env vars, symlinks, config snippets, MCP, and skills.
- Higher value, but requires per-harness config contracts and rollback.

Route:

- Run a local proxy or gateway.
- Convert request formats and route to selected upstreams.
- Needs correctness, streaming compatibility, tool-call compatibility,
  per-provider model mapping, logs, failover, and security decisions.
- Highest complexity and risk.

### Axis 2: Local-first vs Server Gateway

Local-first control plane:

- menubar + local daemon
- reads and writes local harness config
- optional local proxy on `localhost`
- no multi-user billing
- best for Bubu's personal workflow

Server gateway:

- central API endpoint
- multiple upstream accounts
- downstream API keys
- quotas, billing, scheduling, concurrency
- closer to Sub2API
- overkill unless the goal is team sharing or resale-style distribution

### Axis 3: Session Restart vs Hot Switch

Many tools only read config on startup. CC Switch notes that most tools require
restarting terminal/CLI after switching, while Claude Code has some hot-switch
paths.

For Kaji, this suggests a practical UI contract:

- show whether a switch is "active now" or "requires restart"
- expose "open new session with provider X" rather than pretending every switch
  can mutate a running process
- keep existing terminal sessions stable; route new sessions by profile

## Possible Kaji Gauge Direction

### Phase 1: Harness Inventory

Add a local inventory layer, still observe-only:

- configured harnesses: Claude Code, Codex, Gemini CLI, MiniMax, Ark wrappers,
  OpenCode, Kiro
- active credentials/account label where safely discoverable
- quota windows and reset times
- current active sessions by project/cwd
- "can switch", "can route", "read-only" capability badges

Data shape sketch:

```json
{
  "id": "codex",
  "kind": "harness",
  "display_name": "Codex",
  "quota": {
    "five_hour_used_percent": 42,
    "seven_day_used_percent": 18,
    "resets_at": "..."
  },
  "capabilities": {
    "usage": "native-local",
    "account_switch": "unknown",
    "config_switch": "possible",
    "local_proxy": "possible"
  }
}
```

### Phase 2: Profile Registry

Add a local profile registry, without routing yet:

- provider profiles: official OAuth, API key, relay endpoint, local proxy
- model aliases: `fast`, `strong`, `cheap`, `long-context`
- harness bindings: which profile should Codex/Claude/Gemini use for new
  sessions
- health and quota status

This is where Kaji Gauge starts becoming a manager, not just a gauge.

### Phase 3: Safe Config Switching

Implement switching only for harnesses with clear config contracts:

- snapshot old config before write
- atomic write
- validate generated config
- show restart-needed state
- provide rollback

Avoid account credential swapping at first unless the storage format is stable
and user explicitly opts in.

### Phase 4: Optional Local Router

Only after config switching is stable:

- local proxy listens on localhost
- one normalized endpoint per client family, not "one universal magic endpoint"
- adapter boundary per protocol: Anthropic Messages, OpenAI Responses,
  ChatCompletions, Codex app-server paths if legally/technically acceptable
- per-request decision can use quota, cost, current availability, user policy

This should be a separate daemon/process, not embedded in the SwiftUI menubar
app.

## What Not To Copy Blindly

- Do not start with a Sub2API-style server. It brings user management, billing,
  Redis/Postgres, concurrency scheduling, and compliance surface that Kaji Gauge
  does not need yet.
- Do not rely on third-party relay providers as a core assumption. They are
  operationally useful but bad as the foundation for a personal local tool.
- Do not make reverse-engineered subscription-to-API behavior the default path.
  Keep it behind explicit opt-in if ever explored.
- Do not claim hot switching unless the target harness actually supports it.

## Open Questions For Review

1. Is the first useful product a quota cockpit, a config switcher, or a router?
2. Should this live inside Kaji Gauge, or should Kaji Gauge spawn/read from a
   separate `kaji-harnessd` daemon?
3. Which harnesses matter first: Claude Code, Codex, MiniMax/Ark, Gemini CLI,
   OpenCode, Kiro?
4. Do we need account switching, or only provider/model profile switching?
5. Should routing be local-only, or eventually support remote/team use?
6. What is the acceptable risk boundary around reverse-engineered OAuth/proxy
   features?

## Recommendation

Start with Kaji Gauge as the quota and session cockpit:

1. Extend `quota.py` into a structured harness inventory.
2. Add provider/profile metadata, but keep it read-only at first.
3. Show capability badges and restart-needed state.
4. Add safe config switching for one harness at a time.
5. Only then discuss a local router.

This path preserves Kaji Gauge's existing strength: local, transparent,
low-risk visibility. It leaves room for routing later without prematurely
turning the app into a gateway platform.
