# Spec: Goals Surface v2 — 一张清单

> **Status:** approved（2026-08-01）  
> **Date:** 2026-08-01  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [three-horizon-goals](./2026-08-01-three-horizon-goals.md)、[interactive-menu-bar-slots](./2026-08-01-interactive-menu-bar-slots.md)

本切片只收敛 Goals 的菜单栏和 popover 表面，不改三层数据、迁移和周期规则。

## 1. Goal

让 Goals 成为一张打开即读、随手可改的清单：菜单栏只留今日进度，popover 同时看见今天、本周、长期。

## 2. In

- 菜单栏 Goals slot 从 `checklist 0/1` 改为纯文本 `0/1`。
- 点击 `0/1` 仍直达 Goals popover。
- 移除“今天 / 本周 / 长期”segmented control。
- 一个可滚动 popover 内从上到下展示今天、本周、长期。
- 每段直接显示小号 `completed/total`、目标列表和一个紧凑 `+`。
- 今天下方按需显示“昨日未完成”，可移回今天或删除。
- 今天热图留在“今天”段内。
- 移除大号完成计数、Reset 按钮和重复的层级说明。
- 保持现有新增、编辑、勾选、删除、持久化和周期清理。

## 3. Non-goals

- 不改三层数据结构、旧数据迁移、跨日/跨周规则。
- 不把菜单栏变成任务标题跑马灯。
- 不新增提醒、截止时间、排序、归档、拖拽。
- 不改 Quota / Work / System 页面。
- 不发版、不 commit/push。

## 4. Behavior + decisions

### 4.1 Menu bar

```text
[quota rings] [work MM:SS]? [0/1]?
```

- Goals 开：只显示今日有效目标的 `completed/total`。
- Goals 关：slot 完全消失并收回宽度。
- `0/0` 仍显示，作为固定入口。
- 全部完成仍是普通 Mono `1/1`，不变色、不庆祝。
- 点击区域覆盖完整数字和约 4pt 内边距，直达 Goals。

### 4.2 Popover

```text
Goals
────────────────────────
今天        0/1       ＋
30d heatmap
○ 发布一篇 twitter    ⌫

本周        1/2       ＋
● ...
○ ...

长期        0/1       ＋
○ ...
```

- 不再通过 tab/segmented control 切换层级。
- 三段按“今天 → 本周 → 长期”固定顺序展示，用轻 Divider 分隔。
- 段标题是一行：层级名、小号计数、右侧 `+`。
- `+` 是唯一新增入口；点击后在该段末尾新增并立即聚焦。
- 每条仍可直接勾选、编辑、删除。
- 空段显示一行弱化的“暂无目标”，不撑大卡片。
- 今天热图紧跟今天标题；本周和长期不显示热图。
- 不显示 Reset。今天/本周由边界自动清勾选；误勾可再次点击撤销。
- 每次打开 popover 都检查跨日：今天清空，昨日未完成项进入独立区；已完成项只留历史。
- 顶部 Goals header 与副标题保留，现有左右模块翻页保留。

### 4.3 Layout

- 移除当前 28pt 大计数、两枚 Reset/Add chip 和 segmented control。
- 段标题 12–13pt；计数 10–11pt monospaced；说明文字最多一行。
- 目标行沿用 Mono 样式，但减少上下空白。
- 内容超出屏幕时只滚动正文；footer 保持可见。
- Light / Dark 都不得出现系统蓝色选中块。

## 5. Acceptance + Verify

| # | Given | Expected | Verify |
| --- | --- | --- | --- |
| 1 | Goals 开，今日 0/1 | 菜单栏只显示 `0/1`，无 checklist glyph | 自动摘要 + 人工 |
| 2 | Goals 关 | 数字与宽度完全消失 | 自动 + 人工 |
| 3 | 点击菜单栏 `0/1` | 打开 Goals，一屏从今天开始并可向下看周和长期 | 人工 |
| 4 | Goals 打开 | 无 segmented control、无大计数、无 Reset/Add chips | snapshot/人工 |
| 5 | 三层都有内容 | 按今天→本周→长期连续展示，不需点击 tab | snapshot/人工 |
| 6 | 点某段 `+` | 只在该段新增并聚焦 | 自动 store + 人工 |
| 7 | 勾选今天一项 | 页面和菜单栏计数即时更新 | 自动摘要 + 人工 |
| 8 | 编辑或删除任一层目标 | 只修改对应层 | 自动 store + 人工 |
| 9 | 今天为空 | 显示 `0/0` 和弱空态；仍可直接新增 | 人工 |
| 10 | 内容超过可用高度 | 正文可滚动，footer 可见 | 人工 |
| 11 | Light / Dark | 无蓝色 segmented 残留，Mono 对比清楚 | snapshot/人工 |
| B1 | 今日两位数目标 | 菜单栏数字完整，不截断 | 自动宽度 + 人工 |
| B2 | 本周/长期为空 | 两段仍可见，不产生大面积空卡 | 人工 |

## 6. Test map

- `MenuBarSlotLogicTests`：`0/0`、`0/1`、两位数、关闭为 nil。
- 现有 `GoalHorizonModelTests`：三层隔离与周期行为保持全绿。
- snapshot：Light / Dark 的完整 Goals 页面与纯数字 status slot。
- 人工 smoke：三个 `+`、编辑/勾选/删除、滚动、footer、菜单栏直达。

## 7. Likely file touch list

- `Sources/Kaji/StatusItemView.swift`
- `Sources/Kaji/AppDelegate.swift`
- `Sources/Kaji/KajiPopoverView.swift`
- `scripts/snapshot.swift`
- `Tests/KajiTests/`

数据 store 无需改动。范围小，批准后直接 tests → code → smoke，不另写 plan。

## 8. Done

- 验收表全部有自动结果或人工记录。
- `swift test` 与 release build 全绿。
- 菜单栏只显示纯数字今日进度。
- 三层同屏，不再点击 tab。
- 维护者确认新版比当前截图更清楚。
- 未 commit/push/release；smoke 后再决定。

## 9. Rollback

- 仅回退 view 与 status slot 布局；Goals 数据不变、不迁移、不删除。
- 若同屏过长，先恢复正文滚动约束，不恢复 segmented control 作为临时补丁。

## 10. 批准前必读

- **“不要点新的按钮”按“不切 tab”理解。** 每层仍保留一个小 `+`，否则无法表达新目标属于今天、本周还是长期。
- **Reset 被移除。** 日/周自动清理，误勾可撤销；减少一个危险且低频的动作。
- **三层同屏会更长。** 用正文滚动解决，不压缩到难读，也不重新藏进 tab。
- **菜单栏只留 `n/n`。** 更安静，但失去 Goals glyph 的身份提示；点击区域和位置保持稳定作为补偿。

## 11. Status

**Approved（2026-08-01）。** 下一步 tests → code → smoke。
