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
| Done | [integrate/sleep-helper.md](integrate/sleep-helper.md) |
| Done | [integrate/localization.md](integrate/localization.md) |
| Done | [ship/distribution.md](ship/distribution.md) |
| **Approved** | [specs/2026-07-24-lean-modules-v1.md](specs/2026-07-24-lean-modules-v1.md) — 已落地 |
| **Approved** | [specs/2026-07-24-work-status-slot.md](specs/2026-07-24-work-status-slot.md) — focus/break 剩余数字；无 BREAK 文案 |
| **Draft** | [specs/2026-07-25-four-language-baseline.md](specs/2026-07-25-four-language-baseline.md) — English 默认；EN / 中文 / PT-BR / ES；保留老用户选择 |
| **Approved** | [specs/2026-07-24-mono-only.md](specs/2026-07-24-mono-only.md) — 方案 B；已落地 |
| **Approved** | [specs/2026-07-24-cursor-quota.md](specs/2026-07-24-cursor-quota.md) — Cursor 月度外 API / 内 Auto；v0.6.1 |
| **Approved** | [specs/2026-07-31-calm-break.md](specs/2026-07-31-calm-break.md) — 日系自然动态休息页；无 Widget |
| **Approved** | [specs/2026-08-01-three-horizon-goals.md](specs/2026-08-01-three-horizon-goals.md) — 今天 / 本周 / 长期三层计划 |
| **Approved** | [specs/2026-08-01-interactive-menu-bar-slots.md](specs/2026-08-01-interactive-menu-bar-slots.md) — Goals 今日进度；Quota / Work / Goals 分区直达 |
| **Approved** | [specs/2026-08-01-goals-surface-v2.md](specs/2026-08-01-goals-surface-v2.md) — 纯数字今日进度；三层同屏 |
| **Approved** | [specs/2026-08-03-goals-fixed-and-vision.md](specs/2026-08-03-goals-fixed-and-vision.md) — Fixed 整体目标 + Vision |
| **Approved** | [specs/2026-08-03-goal-tags.md](specs/2026-08-03-goal-tags.md) — 轻量分类符号与完成态 |
| **Approved** | [specs/2026-08-03-goals-state-cleanup.md](specs/2026-08-03-goals-state-cleanup.md) — 单一状态、legacy 清理、损坏诊断 |
| **Approved** | [specs/2026-08-04-goal-creation-and-settings-window.md](specs/2026-08-04-goal-creation-and-settings-window.md) — Goals 统一创建面板 + 分类设置窗口 |
| **Approved** | [specs/2026-08-04-goals-entry-and-daily-disk-insights.md](specs/2026-08-04-goals-entry-and-daily-disk-insights.md) — Goals 入口收紧 + 每日文件类型磁盘洞察 |
| **Approved** | [specs/2026-08-04-goals-schedule-notes-and-icons.md](specs/2026-08-04-goals-schedule-notes-and-icons.md) — Schedule 多星期 + 可选说明 + 三形图标 |
| **Approved** | [specs/2026-08-04-disk-display-cleanup.md](specs/2026-08-04-disk-display-cleanup.md) — GB/MB 单位 + 删除建议区 |
| **Approved** | [specs/2026-08-05-ai-news-module.md](specs/2026-08-05-ai-news-module.md) — AI HOT Top 10 第五模块 |
| **Approved** | [specs/2026-08-05-ai-news-list-hover-polish.md](specs/2026-08-05-ai-news-list-hover-polish.md) — 一级信息减法 + 稳定 hover 切换 |
| **Approved** | [specs/2026-08-05-settings-information-architecture-polish.md](specs/2026-08-05-settings-information-architecture-polish.md) — Quota / AI News 分栏；Goals 暂留空 |
| **Approved** | [specs/2026-08-05-local-mcp.md](specs/2026-08-05-local-mcp.md) — v0.7 localhost MCP 读写 Goals |
| Optional | [design/palette.html](design/palette.html) |

## Catalog

### Product

| Doc | Notes |
| --- | --- |
| [product/lean-module-host.md](product/lean-module-host.md) | 小而美优先的模块化方向 |
| [product/architecture-modules.md](product/architecture-modules.md) | 增量模块主机架构草图 |
| [product/vision.md](product/vision.md) | 当前 Vision：AI 时代 Mac 上离个人最近的状态与控制层 |
| [product/2026-08-05-popover-visualization-decision.md](product/2026-08-05-popover-visualization-decision.md) | Popover / 圆环方案讨论与“暂时不重构”决策 |
| [product/2026-08-05-ai-news-prd.md](product/2026-08-05-ai-news-prd.md) | AI News 第五模块 PRD（Draft） |

### Design

| Doc | Notes |
| --- | --- |
| [design/design-language.md](design/design-language.md) | 黑白灰 Mono |
| [design/homepage-shot-guide.zh.md](design/homepage-shot-guide.zh.md) | README 截图指南（内部） |
| [design/palette.html](design/palette.html) | 色板页 |

### Integrate

| Doc | Notes |
| --- | --- |
| [integrate/pet-bridge.md](integrate/pet-bridge.md) | `pet-state.json` contract |

### Ship

| Doc | Notes |
| --- | --- |
| [ship/distribution.md](ship/distribution.md) | Unsigned / Gatekeeper / notarization; source-only releases |
| [ship/releases/](ship/releases/) | Authored GitHub Release notes per tag (`vX.Y.Z.md`) |

### Specs & plans

| Doc | Notes |
| --- | --- |
| [specs/2026-07-24-lean-modules-v1.md](specs/2026-07-24-lean-modules-v1.md) | 已通过并落地 |
| [specs/2026-07-24-work-status-slot.md](specs/2026-07-24-work-status-slot.md) | 已通过：focus/break 剩余 `MM:SS`，无 BREAK |
| [specs/2026-07-24-mono-only.md](specs/2026-07-24-mono-only.md) | 已落地：方案 B，只留黑白灰 |
| [specs/2026-07-24-cursor-quota.md](specs/2026-07-24-cursor-quota.md) | 已通过：外 API / 内 Auto；limits-only；默认可见 → v0.6.1 |
| [specs/2026-07-31-calm-break.md](specs/2026-07-31-calm-break.md) | 已通过：日系自然动态休息页；无 Widget |
| [specs/2026-08-01-three-horizon-goals.md](specs/2026-08-01-three-horizon-goals.md) | 已通过：今天 / 本周 / 长期三层计划 |
| [specs/2026-08-01-interactive-menu-bar-slots.md](specs/2026-08-01-interactive-menu-bar-slots.md) | 已通过：Goals 今日进度；Quota / Work / Goals 分区直达 |
| [specs/2026-08-01-goals-surface-v2.md](specs/2026-08-01-goals-surface-v2.md) | 已通过：纯数字今日进度；今天 / 本周 / 长期同屏 |
| [specs/2026-08-03-goals-fixed-and-vision.md](specs/2026-08-03-goals-fixed-and-vision.md) | 已通过：Fixed 整体目标 + Vision |
| [specs/2026-08-03-goal-tags.md](specs/2026-08-03-goal-tags.md) | 已通过：轻量分类符号与完成态 |
| [specs/2026-08-03-goals-copy-cleanup.md](specs/2026-08-03-goals-copy-cleanup.md) | 已通过：Goals 解释文案减法 |
| [specs/2026-08-03-goals-state-cleanup.md](specs/2026-08-03-goals-state-cleanup.md) | 已通过：单一状态、legacy 清理、损坏诊断 |
| [specs/2026-08-04-goal-creation-and-settings-window.md](specs/2026-08-04-goal-creation-and-settings-window.md) | 已通过：Goals 统一创建面板 + 分类设置窗口 |
| [specs/2026-08-04-goals-entry-and-daily-disk-insights.md](specs/2026-08-04-goals-entry-and-daily-disk-insights.md) | 已通过：Goals 入口收紧 + 每日文件类型磁盘洞察 |
| [specs/2026-08-04-goals-schedule-notes-and-icons.md](specs/2026-08-04-goals-schedule-notes-and-icons.md) | 已通过：Schedule 多星期 + 可选说明 + 三形图标 |
| [specs/2026-08-04-disk-display-cleanup.md](specs/2026-08-04-disk-display-cleanup.md) | 已通过：GB/MB 单位 + 删除建议区 |
| [specs/2026-08-05-ai-news-module.md](specs/2026-08-05-ai-news-module.md) | 已通过：AI HOT Top 10、5h 刷新与 hover digest |
| [specs/2026-08-05-ai-news-list-hover-polish.md](specs/2026-08-05-ai-news-list-hover-polish.md) | 已通过：来源移入详情、相邻 hover 即时切换 |
| [specs/2026-08-05-settings-information-architecture-polish.md](specs/2026-08-05-settings-information-architecture-polish.md) | 已通过：Quota / AI News 职责拆分，Goals 只保留设置入口 |
| [specs/2026-08-05-local-mcp.md](specs/2026-08-05-local-mcp.md) | 已通过：不改 v0.7 Goals UI，仅增加 localhost MCP |
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
  specs/
  plans/
```

No public Pages landing — README + Releases only.
