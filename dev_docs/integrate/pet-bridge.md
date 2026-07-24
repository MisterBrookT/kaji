# Kaji Pet Bridge

Kaji publishes quota state for desktop-pet runtimes. Kaji does not own pet
rendering, animation, or asset generation.

```text
quota.py -> QuotaStore -> PetBridge -> ~/Library/Application Support/Kaji/pet-state.json
```

## State File

```text
~/Library/Application Support/Kaji/pet-state.json
```

External runtimes can poll this file and map `animationState` to their own
sprites, Live2D motions, or pet states.

## Schema

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-06-27T10:00:00Z",
  "animationState": "review",
  "reason": "quota_pressure",
  "summary": "Provider quota is getting tight.",
  "severity": 0.82,
  "dominantProvider": "provider-id",
  "providers": [
    {
      "id": "provider-id",
      "displayName": "Provider B",
      "fiveHourPercent": 82,
      "sevenDayPercent": 64,
      "fiveHourResetsAt": "2026-06-27T11:00:00Z",
      "sevenDayResetsAt": "2026-07-02T08:18:45Z",
      "dataStatus": "ok",
      "pressure": "warn"
    }
  ]
}
```

## Animation Mapping

| `animationState` | Meaning | Suggested Pet Behavior |
| --- | --- | --- |
| `idle` | Quota healthy and not rising | Calm idle |
| `running` | Usage is increasing | Working / focused animation |
| `review` | Quota pressure, usually >=80% | Attention / review animation |
| `waiting` | Quota near limit or no provider data yet | Waiting / asking animation |
| `failed` | Kaji could not refresh data | Failed / confused animation |

## Reasons

| `reason` | Meaning |
| --- | --- |
| `quota_healthy` | Data exists and quota pressure is low |
| `quota_active` | Recent samples show usage increasing |
| `quota_pressure` | Highest 5h or 7d usage is >=80% |
| `quota_limit` | Highest 5h or 7d usage is >=95% |
| `no_provider_data` | Kaji has no readable provider data yet |
| `quota_refresh_failed` | Reader refresh failed, last good data may still exist |
| `python_missing` | Kaji cannot find a working `python3` |

## Hatch-Pet Boundary

`hatch-pet` creates runtime-compatible pet assets:

```text
concept/reference -> 9 animation rows -> spritesheet.webp + pet.json
```

Kaji consumes the result only through runtime state. The product boundary stays:

```text
Kaji = quota/status data layer
Pet runtime = visual embodiment
hatch-pet = asset compiler
```
