# Internal docs (`dev_docs`)

维护者 / agent 的工作笔记。**不是**公开 GitHub 文档站。

公开文档暂缓。方向约束：[AGENTS.md](../AGENTS.md)。

文档不搞中英对照：一份就够，中英混用按写作者方便。

## Review checklist

| Status | Doc |
| --- | --- |
| Done | [design/design-language.md](design/design-language.md) |
| Done | [design/homepage-shot-guide.zh.md](design/homepage-shot-guide.zh.md) |
| Done | [product/lean-module-host.md](product/lean-module-host.md) |
| Done | [product/architecture-modules.md](product/architecture-modules.md) |
| Done | [integrate/pet-bridge.md](integrate/pet-bridge.md) |
| Done | [ship/distribution.md](ship/distribution.md) |
| **Approved** | [specs/2026-07-24-lean-modules-v1.md](specs/2026-07-24-lean-modules-v1.md) — 已落地 |
| **Review** | [specs/2026-07-24-work-status-slot.md](specs/2026-07-24-work-status-slot.md) — Work 菜单栏倒计时槽（待审） |
| **Approved** | [specs/2026-07-24-mono-only.md](specs/2026-07-24-mono-only.md) — 方案 B；待实现 |
| Parked | [index.html](index.html) |
| Optional | [design/palette.html](design/palette.html) |

## Catalog

### Product

| Doc | Notes |
| --- | --- |
| [product/lean-module-host.md](product/lean-module-host.md) | 小而美优先的模块化方向 |
| [product/architecture-modules.md](product/architecture-modules.md) | 增量模块主机架构草图 |

### Design

| Doc | Notes |
| --- | --- |
| [design/design-language.md](design/design-language.md) | 黑白灰 Mono |
| [design/homepage-shot-guide.zh.md](design/homepage-shot-guide.zh.md) | README / 主页截图指南（内部） |
| [design/palette.html](design/palette.html) | 色板页 |

### Integrate

| Doc | Notes |
| --- | --- |
| [integrate/pet-bridge.md](integrate/pet-bridge.md) | `pet-state.json` contract |

### Ship

| Doc | Notes |
| --- | --- |
| [ship/distribution.md](ship/distribution.md) | Unsigned / Gatekeeper / notarization |

### Specs & plans

| Doc | Notes |
| --- | --- |
| [specs/2026-07-24-lean-modules-v1.md](specs/2026-07-24-lean-modules-v1.md) | 已通过并落地 |
| [specs/2026-07-24-work-status-slot.md](specs/2026-07-24-work-status-slot.md) | draft 待审：work 状态栏槽 |
| [specs/2026-07-24-mono-only.md](specs/2026-07-24-mono-only.md) | **Review**；只留黑白灰 Mono light/dark |
| `plans/` | 可选；大任务 / 多 agent 零上下文时再用 |

### Assets

[`assets/`](assets/)

## Layout

```text
dev_docs/
  README.md
  assets/
  product/
  design/
  integrate/
  ship/
  specs/     # next
  plans/     # next
  index.html # parked
```
