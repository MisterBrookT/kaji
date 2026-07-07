# Harness Pool Plan

Date: 2026-06-17

This plan starts from Bubu's actual workflow:

1. See remaining quota across all harnesses.
2. Continue a task when one harness runs out.
3. Eventually let one task share a pool of multiple harness quotas.

## One-line Read On Existing Projects

- Sub2API: server-side subscription/API gateway that pools upstream accounts,
  schedules requests, tracks token billing, and exposes downstream API keys.
- CC Switch: local desktop control panel that owns provider presets, config
  switching, usage logs, MCP/Skills sync, and optional local proxy takeover.
- cc-account-switcher: small Claude Code auth-state switcher; useful proof that
  account switching can be tiny when scoped narrowly.
- CCS: hybrid account switcher plus proxy/dashboard; confirms the ecosystem is
  splitting into local switchers and API proxy gateways.

Borrow this:

- from Sub2API: account/provider pool model, sticky session idea, usage/rate
  accounting vocabulary.
- from CC Switch: provider profile registry, config backup/atomic write, tray
  switching, restart-needed state, usage dashboard shape.
- from cc-account-switcher: keep auth switching separate from provider/profile
  switching; do not make it the first feature.
- from CCS: visual dashboard + proxy can be a later layer, not the foundation.
- from openclaw-wsl-toolkit: use Volcengine OpenAPI `GetAFPUsage` as the
  official Ark quota source, normalize `Used/Quota/ResetTime`, and explicitly
  mark unbound/empty plan responses as unknown instead of inventing quota.
- from quota-peek: AK/SK env-file wiring for the Volcengine quota card.

Avoid this:

- billing/multi-user/server gateway before we need it.
- reverse-engineered subscription-to-API routing as a default path.
- claiming hot-switching for harnesses that only read config at startup.

## Phase 1: Harness Radar

Goal: answer one question fast: "which harness should I use right now?"

Scope:

- show each configured harness and its quota/reset state
- show data confidence: official quota, local-log estimate, session count only,
  or configured but unknown
- show current sessions by project/cwd where the source exposes them
- show recommendation: available, near limit, exhausted, stale, unknown
- no config writes, no credential mutation, no proxy

Initial harness set:

| Harness | Current source | Phase 1 status |
|---|---|---|
| Claude Code | `~/.claude` logs + Anthropic OAuth usage endpoint | already mostly supported |
| Codex | `~/.codex/sessions` + `codex app-server account/rateLimits/read` | already mostly supported |
| MiniMax | `mmx quota show --output json` | already wired |
| Ark Agent Plan | fish `claude-ark` / `arkp`, endpoint `/api/plan` | add provider + quota reader |
| Ark Coding Plan | fish `claude-ark-coding` / `arkcp`, endpoint `/api/coding` | add provider + quota reader |
| Gemini CLI | likely config/session based; quota API unclear | later, start as configured/unknown |
| OpenCode | local storage usage parse | already has usage estimate |
| Kiro | local sessions have no token counts | session count only |

### Ark Implementation Notes

Current local wiring:

- `claude-ark`: Claude Code harness with
  `ANTHROPIC_BASE_URL=https://ark.cn-beijing.volces.com/api/plan`
- `arkp`: one-shot Agent Plan headless, same `/api/plan`
- `claude-ark-coding`: Claude Code harness with
  `ANTHROPIC_BASE_URL=https://ark.cn-beijing.volces.com/api/coding`
- `arkcp`: one-shot Coding Plan headless, same `/api/coding`
- credentials live under `~/.config/ark/` as separate Agent/Coding keys

Official API lead:

- Volcengine Ark API docs list Agent Plan usage APIs:
  `GetAFPUsage`, `GetSeatAFPUsage`, `GetUsageDetails`,
  `GetSeatUsageDetails`, `ListSeatAFPUsage`.
- The same docs list Coding Plan usage APIs:
  `GetSeatInfoUsage`, `ListSeatInfoUsages`, `ListSeatInfos`.
- Console docs also expose usage statistics by day/hour and endpoint.

Phase 1 Ark reader design:

1. Detect configured Ark plans by checking that the key files exist, without
   printing or reading secrets into logs.
2. Add two provider ids: `ark-agent` and `ark-coding`; do not collapse them,
   because they have different endpoints and likely different quotas.
3. Implement a small `ark_limits()` reader in `quota.py`.
4. Preferred path: call official Ark plan usage APIs with Volcengine signing or
   an available SDK/CLI if present.
5. Fallback path: emit provider as configured with `limits: null` and
   `confidence: "configured-unknown"`.
6. UI should show `Ark Agent` / `Ark Coding` as visible providers even when the
   exact quota is unknown.

Open issue: the exact auth/signing method for plan usage APIs needs a short
implementation spike. The generation endpoint uses bearer API keys, but
management APIs may require Volcengine AK/SK signing. Treat this as the main
Ark risk.

### Phase 1 Data Contract

Extend the current JSON without breaking existing Swift decoding:

```json
{
  "ark-agent": {
    "tokens_today": 0,
    "sessions_today": 0,
    "limits": {
      "five_hour_used_percent": 30,
      "seven_day_used_percent": 12,
      "five_hour_resets_at": "2026-06-17T18:00:00Z"
    },
    "confidence": "official-quota",
    "capabilities": {
      "usage": "official-api",
      "handoff": "new-session",
      "config_switch": "env-wrapper",
      "route": "anthropic-compatible"
    }
  }
}
```

Compatibility rule: existing `tokens_today`, `sessions_today`, and `limits`
stay additive; new keys must be optional.

## Phase 2: Task Handoff

Goal: when one harness runs out, the task continues in another harness with
minimal friction.

This is not same-process hot switching. It is a structured handoff:

- capture cwd, branch, dirty diff, recent commands, current objective
- produce a `handoff.md` with a concise continuation prompt
- launch the target harness in a new session when possible
- record `from_harness -> to_harness` so the chain is visible

First version:

- manual button/menu action: "Continue in Codex", "Continue in Ark Coding",
  "Continue in Claude"
- writes `.kaji/handoffs/YYYYMMDD-HHMM-<from>-to-<to>.md`
- does not mutate the old session

This matches the real need: task continuity, not magical in-session backend
mutation.

## Phase 3: Profile Registry

Goal: make new sessions deterministic.

Add local profiles:

- `claude-official`
- `codex-official`
- `ark-agent`
- `ark-coding`
- `minimax-m3`
- future relay profiles if explicitly configured

Each profile should declare:

- launch command or environment wrapper
- model family and default model
- quota source
- restart/hot-switch semantics
- risk level

This layer enables "open a new session with profile X" before any proxy exists.

## Phase 4: Local Router

Goal: one task can consume quota from multiple harnesses under policy.

Defer until Phase 1-3 are useful.

Likely architecture:

- `kaji-harnessd` local daemon
- protocol adapters per family, not one universal adapter
- policy engine based on quota, cost, task type, model capability, and failure
  state
- request logs and replay-safe handoff boundaries

Hard problems:

- streaming compatibility
- tool-call compatibility
- model/context differences
- state continuity after failover
- provider terms and account safety

## Immediate Next Step

Implement Phase 1 in the smallest useful slice:

1. Add `ark-agent` and `ark-coding` provider metadata to Swift display config.
2. Add `confidence` and `capabilities` optional fields to quota JSON/model.
3. Add configured-but-unknown Ark detection first.
4. Spike official Ark usage API signing and map its response into `limits`.
5. Update UI to distinguish "quota unknown" from "no data".

Current implementation note:

- Done: `ark-agent` / `ark-coding` provider metadata and configured-key
  detection.
- Done: `quota.py --json` emits Ark entries when `~/.config/ark/agent-key` or
  `~/.config/ark/key` exists.
- Done: optional Volcengine OpenAPI V4 signing path. If
  `VOLCENGINE_ACCESS_KEY_ID` + `VOLCENGINE_SECRET_ACCESS_KEY` (or the shorter
  `VOLC_ACCESS_KEY_ID` + `VOLC_SECRET_ACCESS_KEY`) are present, `quota.py`
  attempts `GetAFPUsage` / `GetSeatInfoUsage` and maps percent-like fields into
  `limits`.
- Verified: local Volcengine OpenAPI AK/SK works for `GetAFPUsage`. The
  response uses `AFPFiveHour` / `AFPWeekly` with `Used`, `Quota`, and
  `ResetTime`; `quota.py` maps these into existing percent/reset fields.
- Open: `GetSeatInfoUsage` requires either `SeatID` or `ProjectName`. Add
  `VOLCENGINE_ARK_SEAT_ID` or `VOLCENGINE_ARK_PROJECT_NAME` to
  `~/.config/kaji-gauge/volcengine.env` when the Coding Plan seat/project is
  known.
- Open-source check: public implementations found so far cover Agent Plan
  `GetAFPUsage` but do not auto-discover Coding Plan `SeatID`. Treat Coding
  Plan as configured-but-unknown unless the seat id is provided or a later
  console/API discovery path proves reliable.
- Fixed: Swift now keeps every display-ready provider emitted by `quota.py` in
  `QuotaStore.providers`; visibility filtering is only applied in views via
  `Prefs.visibleProviders`. This lets configured Ark providers appear in the
  provider toggle list even when they are not default-visible rings, without
  surfacing diagnostic-only rows such as Kiro/OpenCode.
- Verified: `python3 -m py_compile Resources/quota.py`, `swiftc -typecheck
  Sources/KajiGauge/*.swift`, direct `swiftc` temporary app bundle launch.
