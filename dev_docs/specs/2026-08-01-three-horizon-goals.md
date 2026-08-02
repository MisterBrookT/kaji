# Spec: Three-horizon Goals — 三层计划

> **Status:** approved（2026-08-01）  
> **Date:** 2026-08-01  
> **Branch:** 实现时新开 `feat/three-horizon-goals`  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [lean-modules-v1](./2026-07-24-lean-modules-v1.md)、[AGENTS.md](../../AGENTS.md)

本稿只定义 Goals 本体。菜单栏展示与点击分区由 [interactive-menu-bar-slots](./2026-08-01-interactive-menu-bar-slots.md) 单独定义。

## 1. Goal

用户能在 Goals popover 内分别维护今天、本周、长期三个层级的计划，随时添加、完成或结束一项目标。

## 2. In

- Goals popover 增加三个固定层级：今天、本周、长期。
- 每层支持新增、改名、完成、删除。
- 今天的完成状态按本地自然日重置；本周按本地日历周重置；长期不自动重置。
- 迁移现有 `DailyGoalStore` 数据，保留每日目标、当日完成状态与 35 天历史。
- 今天层继续显示现有 35 天完成热图；本周、长期不伪造历史统计。
- UI 保持现有黑白灰 Mono 语言。

## 3. Non-goals

- 不定义菜单栏 icon、完成计数或点击分区。
- 不做截止时间、日历、通知、优先级、标签、拖拽排序、子任务。
- 不做 Today / Calendar / Reminders / 云同步集成。
- 不把 Goals 改为默认开启。
- 不修改 Quota、Work、System 模块，不发版。

## 4. Behavior + decisions

### 4.1 三个层级

Goals 页内使用紧凑 segmented control：

| 层级 | 用途 | 自动重置 |
| --- | --- | --- |
| 今天 | 当前自然日要做的事 | 日期变化时清空；未完成项进入“昨日未完成” |
| 本周 | 当前日历周要推进的事 | 周标识变化时仅清完成状态，标题保留 |
| 长期 | 无固定周期的方向或目标 | 永不自动重置 |

进入 Goals 页默认打开“今天”；同次进程内记住最近选择的层级，不新增持久化偏好。来自菜单栏 Goals slot 的打开请求总是选择“今天”，由配套 spec 定义。

每层：

- 允许空列表。
- `Add` 在当前层新增一条并直接聚焦编辑。
- `Return` 或失焦结束编辑并保存非空标题。
- 标题去掉首尾空白后为空的条目，在结束编辑时删除，不计入统计。
- 勾选立即标记完成；再次点击可撤销。
- 删除立即结束该项目，不要求至少保留一条。
- 展示顺序保持创建顺序；本切片不做排序。

### 4.2 统计与 reset

- 页头计数显示当前层 `completed/total`。
- “今天”显示现有 35 天热图；跨日后清空。
- “昨日未完成”仅保留上一日未完成项，可移回今天或删除；不会无限累积旧日 backlog。
- “本周”显示本周范围和“下周清空完成状态”，不显示热图。
- “长期”显示“不自动清空”，不显示热图。
- 手动 `Reset` 只清当前层完成状态，不删除标题，不影响其他层。
- 日/周切换在 store 初始化和 app 活跃时检查，避免跨日常驻时继续显示旧完成状态。
- 日历周使用 `Calendar.current` 的 `yearForWeekOfYear + weekOfYear`，遵循用户地区的周起始规则。

### 4.3 数据与迁移

新模型按 horizon 分库存储：

1. 若新格式不存在，读取现有 `dailyGoals`、`dailyGoalsDayKey`、`dailyGoalsHistory`。
2. 现有每日条目原样成为“今天”；UUID、标题和当日完成状态不变。
3. 现有 35 天历史原样保留，仍只代表“今天”的完成情况。
4. “本周”和“长期”初始为空。
5. 成功写入新格式后记录 migration version；后续启动不得重复导入。
6. 解码失败时不覆盖原 key；回退为空的新层级，并保留旧数据供回滚或修复。

现有默认三条每日目标仅用于从未产生过任何 Goals 数据的全新安装；迁移用户不额外插入示例。

## 5. Acceptance + Verify

| # | Given | Expected | Verify |
| --- | --- | --- | --- |
| 1 | Goals 页首次打开 | 默认“今天”，显示今日计数与热图 | 人工 |
| 2 | 在任一层 Add | 当前层新增空条目并获得输入焦点 | 人工 |
| 3 | 输入标题后 Return 或失焦 | 标题保存；重启后仍在 | 自动：store；人工：焦点 |
| 4 | 点击未完成项目 | 立即变为完成并更新当前层计数 | 自动 + 人工 |
| 5 | 删除项目 | 只从当前层移除，允许列表变空 | 自动 + 人工 |
| 6 | 日期变化 | 今天标题保留、完成状态清空；历史记下切换前结果 | 自动：注入 calendar/date |
| 7 | 日历周变化 | 本周标题保留、完成状态清空；今天与长期不受影响 | 自动：注入 calendar/date |
| 8 | 长期项目完成后跨日、跨周 | 完成状态不变 | 自动 |
| 9 | 当前层点 Reset | 只清该层勾选，不删标题、不改其他层 | 自动 + 人工 |
| 10 | 旧版 Daily Goals 数据首次启动 | 条目、UUID、标题、当日状态及历史无损进入“今天” | 自动：迁移 fixture |
| 11 | 迁移后再次启动 | 不重复导入，不产生重复条目 | 自动 |
| 12 | 关闭再开启 Goals | 三层数据完整保留 | 自动：持久化；人工 |
| 13 | 当前层为空 | 显示安静空态，仍可 Add；无占位假任务 | 人工 |
| B1 | 旧数据损坏 | 不 crash，不覆盖旧 key；新 store 可用 | 自动 |
| B2 | 空白条目 Return 或失焦 | 删除空条目，不计入 total | 自动 + 人工 |
| B3 | 跨年周 | 周 key 不碰撞，按本地 Calendar 正确重置 | 自动 |

## 6. Test map

- `GoalHorizonStoreTests`：用例 3–12、B1–B3；注入 `UserDefaults` suite、日期与 `Calendar`。
- 人工 smoke：用例 1–5、9、12–13，重点检查输入焦点和即时计数。
- 所有自动用例统一由 `swift test` 执行。

## 7. Likely file touch list

- `Sources/Kaji/DailyGoalStore.swift`
- `Sources/Kaji/KajiPopoverView.swift`
- `Sources/Kaji/AppDelegate.swift`：仅跨日/跨周刷新接线
- `Sources/KajiCore/`
- `Tests/KajiTests/`

范围清楚且触点集中，批准后跳过独立 plan，直接 tests → code → smoke。

## 8. Done

- 验收表每项有自动结果或人工 smoke 记录。
- `swift test` 全绿。
- 旧 Daily Goals 无损迁移，重复启动不重复导入。
- 三层可独立维护，添加、完成、结束操作即时生效。
- 未 commit、未 push、未发版；维护者 smoke 后再决定后续。

## 9. Rollback

- 旧 `dailyGoals*` keys 不删除。
- 新格式使用独立 key 和 migration version；回退旧版本仍可读取原每日数据。
- 若迁移有缺陷，先停用新格式读取并修 migration，不清空用户数据。

## 10. 批准前必读

- **每天/每周只清勾选，不清标题。** 它们是周期计划模板；自动删除标题会造成真实内容丢失。
- **删除代表“结束并移除”，完成代表“保留但已做完”。** 本切片不另设 archive；否则三层模型会膨胀成任务管理器。
- **历史只统计今天。** 把周和长期塞进现有热图会改变指标含义。
- **旧 key 暂不删除。** 少量重复存储换取安全回滚。

## 11. Status

**Approved（2026-08-01）。** 下一步 tests → code → smoke。
