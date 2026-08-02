# Spec: Interactive Menu Bar Slots — Goals 进度与模块直达

> **Status:** approved（2026-08-01）  
> **Date:** 2026-08-01  
> **Branch:** 实现时新开 `feat/interactive-menu-bar-slots`  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [work-status-slot](./2026-07-24-work-status-slot.md)、[three-horizon-goals](./2026-08-01-three-horizon-goals.md)、[AGENTS.md](../../AGENTS.md)

本稿只定义菜单栏的可见摘要与点击目标。Goals 数据模型由配套 spec 定义。

## 1. Goal

菜单栏安静展示今日 Goals 完成情况，并让用户点击 Goals 或 Work 区域直接进入对应 popover 页面。

## 2. In

- Goals 启用时显示 `checklist completed/total`，例如 `☷ 2/4`。
- 点击 Goals slot 直接打开 Goals 页的“今天”层。
- 点击 Work 倒计时 slot 直接打开 Work / Break 页；休息中仍进入同一页并显示当前休息状态。
- 点击 Quota rings 直接打开 Quota 页。
- Goals、Work 关闭时各自 slot 消失，不留下点击热区。
- 单个 `NSStatusItem` 内实现多个明确点击区域；不创建多个菜单栏 item。
- Mono、紧凑、无动画。

## 3. Non-goals

- 菜单栏不显示目标标题、周计划或长期目标。
- 不显示红点、彩色完成态、百分比环、提醒动画。
- 不从菜单栏直接新增或勾选；点击后在 popover 完成操作。
- 不新增右键菜单、通知、快捷键。
- 不改变模块默认开关。
- 不重做 Work / Break 内容页。

## 4. Behavior + decisions

### 4.1 视觉

```text
[quota rings] [work MM:SS]? [checklist 2/4]?
```

Goals slot：

- SF Symbol `checklist`，约 13–14pt、medium、Mono。
- 右侧显示今天有效目标的 `completed/total`，monospaced digits，例如 `2/4`。
- 今日没有目标时显示 `checklist 0/0`，仍提供添加入口；不使用红点或 `+` 制造紧迫感。
- 全部完成仍显示普通 Mono `4/4`，不变色、不庆祝。
- 今日条目或完成状态变化后，下一 runloop 更新计数。

计数中的 `total` 忽略正在编辑的空白条目，与 Goals 页头一致。

### 4.2 点击目标

| 点击区域 | 打开页面 |
| --- | --- |
| Quota rings | Quota |
| Work `MM:SS` | Work / Break |
| Goals `checklist n/n` | Goals，并选择“今天” |
| slot 间空白 | Quota，作为安全回落 |

- popover 已打开时点击另一个 slot，切换到目标页，不只关闭 popover。
- Work 处于 focus、breakDue 或 breaking，点击目标始终是 Work / Break 页；页面内部展示当前 phase。
- Goals slot 的命中区域覆盖 icon、数字及约 4pt 内边距。
- Work slot 的命中区域覆盖完整倒计时及约 4pt 内边距。
- Hover 使用轻微系统态或指针反馈即可；不加 tooltip 气泡。

### 4.3 事件结构

当前整条 `NSStatusBarButton` 的单一 action 无法表达不同 slot 的目标页。实现必须让 SwiftUI slot 产生明确 action，或按可靠几何命中测试路由点击；不得根据“上次页面”猜测。

优先结构：

```text
NSStatusItem
  StatusItemView
    quota Button
    work Button?
    goals Button?
```

若 AppKit 对嵌套 button 事件有冲突，允许由 hosting view 按已知 slot frame 路由，但必须自动测试 frame → destination 纯逻辑，并人工验证不同缩放与多 provider。

### 4.4 宽度

- Goals slot 宽度按 icon + `n/n` 自适应，计数到两位数仍不截断。
- 继续限制最多四个 provider rings。
- Work / Goals 关闭后立即收回对应宽度。
- 不为三位数专门优化；`100/100` 可完整显示，但超过此规模不属于产品目标。

## 5. Acceptance + Verify

| # | Given | Expected | Verify |
| --- | --- | --- | --- |
| 1 | Goals 关闭 | 无 Goals slot、无残留宽度或点击热区 | 自动：模型；人工 |
| 2 | Goals 开，今日 2/4 | 显示 Mono `checklist 2/4` | 自动 + 人工 Light/Dark |
| 3 | 今日 0 项 | 显示 `checklist 0/0`，可点击添加入口 | 自动 + 人工 |
| 4 | 今日从 2/4 勾到 3/4 | 下一 runloop 显示 `3/4` | 自动：摘要模型；人工 |
| 5 | 点击 Goals slot | popover 打开到 Goals / 今天 | 自动：路由模型；人工 |
| 6 | 点击 Work 倒计时，当前 focus | popover 打开到 Work / Break，显示 focus | 自动 + 人工 |
| 7 | 点击 Work 倒计时，当前 breaking | popover 打开到 Work / Break，显示休息状态 | 自动 + 人工 |
| 8 | 点击 Quota ring | popover 打开到 Quota | 自动 + 人工 |
| 9 | popover 已开在 Goals，再点 Work slot | popover 保持打开并切到 Work / Break | 人工 |
| 10 | Work 或 Goals 关闭 | 对应 slot、宽度与点击目标立即消失 | 自动 + 人工 |
| 11 | 四个 provider + Work + Goals | 各区域可读、可点击，无重叠 | 人工 |
| B1 | 今日完成数/总数为两位数 | 文案完整，不截断 | 自动：宽度模型；人工 |
| B2 | 点击 slot 间空白 | 打开 Quota，不 crash、不误触隐藏模块 | 自动 + 人工 |
| B3 | Goals 在点击后被关闭 | 页面回落 Quota，slot 消失 | 自动 + 人工 |

## 6. Test map

- `MenuBarSlotSummaryTests`：用例 1–4、B1。
- `MenuBarSlotRoutingTests`：用例 5–8、10、B2–B3。
- 人工 smoke：全部点击命中、popover 已打开时切页、Light/Dark、四 provider 拥挤态。
- 所有自动用例统一由 `swift test` 执行。

## 7. Likely file touch list

- `Sources/Kaji/StatusItemView.swift`
- `Sources/Kaji/AppDelegate.swift`
- `Sources/Kaji/KajiPopoverView.swift`：接受外部目标页与 Goals horizon
- `Sources/KajiCore/`
- `Tests/KajiTests/`

这份与 Goals 数据 spec 共享 `AppDelegate`、`KajiPopoverView`。实现顺序：先 Goals 本体，再本 spec；不要并行修改共享文件。

## 8. Done

- 验收表每项有自动结果或人工 smoke 记录。
- Goals 今日计数准确、即时更新。
- Quota、Work、Goals 三个区域分别直达对应页。
- `swift test` 全绿，手工命中测试通过。
- 仍只有一个 `NSStatusItem`。
- 未 commit、未 push、未发版；维护者 smoke 后再决定后续。

## 9. Rollback

- 删除交互 slot 接线即可恢复现有整条 status item action。
- Goals 数据由独立 spec/store 持久化；回滚本 spec 不删除任何计划。
- 若分区命中不可靠，先回退为整条点击 Quota，不保留半可靠路由。

## 10. 批准前必读

- **菜单栏会比现在更宽。** `checklist n/n` 提供真正有用的今日进度，但会增加约 32–48pt；通过模块开关完整收回。
- **每个 slot 是不同入口。** Work 倒计时直达 Work / Break，Goals 计数直达 Goals / 今天；这是本 spec 的核心，不接受“整条都打开上次页面”。
- **`0/0` 仍显示。** 入口价值高于空态省下的几像素；隐藏会让用户无法从固定位置随时添加。
- **嵌套点击是主要技术风险。** 必须在多 provider、popover 已打开、Light/Dark 下人工验证，不以单元测试替代。

## 11. Status

**Approved（2026-08-01）。** 下一步 tests → code → smoke。
