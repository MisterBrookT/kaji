# Spec: Work Status Slot — 菜单栏倒计时槽

> **Status:** draft — 待审  
> **Date:** 2026-07-24  
> **Branch:** `docs/lean-module-host`（实现时可再开 `feat/work-status-slot`）  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [specs/2026-07-24-lean-modules-v1.md](./2026-07-24-lean-modules-v1.md)（已通过）、[product/lean-module-host.md](../product/lean-module-host.md)、[product/architecture-modules.md](../product/architecture-modules.md)、[AGENTS.md](../../AGENTS.md)

这份是 **可验收 feature spec**。  
lean-modules-v1 已落地（`enabledModules`、瘦默认、popover 过滤）。本切片补上产品清单里的下一步：**可组合状态栏槽位**。

对本切片：**不强制另写 plan**；下一步按 §6 用例写纯逻辑测试，再接线 UI。

---

## 1. 用户目标

启用 `work` 时，在菜单栏 **一眼看到** 当前 focus / break 还剩多久，不必打开 popover。

一句话成功标准：

> Work 开 = 环旁有紧凑倒计时/状态；Work 关 = 菜单栏仍只有用量环（安静）。

---

## 2. 范围内（In）

1. 当 `prefs.isModuleEnabled(.work)` 为真时，`StatusItemView` 在用量环右侧增加 **work status slot**
2. 槽位内容随 `WorkSessionPhase` 与时钟更新（约 1s，跟现有 session tick）
3. 可组合布局：`HStack` = quota rings（`quota` 恒开，始终有）+ 可选 work slot
4. `work` 关闭时：不渲染 work slot；`statusItem` 宽度回到仅环
5. 视觉跟现网菜单栏一致：Mono / `blackWhite` 自适应（与 `AppDelegate` 当前强制样式一致）；不引入彩色主题 glyph
6. 纯展示模型可抽到 `KajiCore`（便于 `swift test`），UI 只消费模型

## 3. 范围外（Non-goals）

本 spec **不做**：

- Ice / 管理其它 App 的菜单栏图标
- 新模块 ID、插件市场、动态 bundle
- GitHub Release / 版本号 / README 营销改写
- 重写 Break overlay / 运动关卡 / 场景图（现有路径可继续；本切片只加菜单栏槽）
- System / Goals 状态栏 glyph
- 删除 Color / Calm / Playful Settings 债（另开 Mono-only 若需要）
- 点击槽位的独立手势（整条 status item 仍打开 popover，与现网一致）

---

## 4. 行为表


| 条件 | 菜单栏 work slot |
| --- | --- |
| `work` **未启用** | **无槽**（即使控制器里仍有旧 phase，也不得漏出） |
| `work` 启用 · `phase == .working` | 显示 **剩余 focus** `MM:SS`（`focusTarget - workElapsed`，下限 `00:00`） |
| `work` 启用 · `phase == .breakDue` | 显示固定区分 cue：**`BREAK`**（全大写、紧凑等宽感；非倒计时数字） |
| `work` 启用 · `phase == .breaking` | 显示 **剩余 break** `MM:SS`（现有 `breakClock` 语义） |
| 样式 | Mono / blackWhite：浅色黑字、深色白字；字号贴菜单栏高度（约 11–12pt），不抢环 |
| 更新 | phase 或秒级时钟变化 → 下一次 `updateStatusItem` 反映新文案 |

**拍板（不留开放选项）：**

| 议题 | 决定 | 理由 |
| --- | --- | --- |
| working 显示 | **剩余** focus `MM:SS`，不是 elapsed | 对齐「一眼还剩多久」；与 break 倒计时方向一致 |
| breakDue | 固定文案 **`BREAK`** | 与数字态明显区分；短、可读、无需新图标资产 |
| 槽位位置 | 环 **右侧** | 左环右节奏，符合「quota 主、work 辅」 |
| 仅 work、无可见 provider | 仍保留至少一枚占位环（现网行为）+ work slot | 不改 lean-modules-v1 的 quota 强制常开 |

---

## 5. 布局

```text
NSStatusItem
  └─ StatusItemView
        HStack(spacing ≈ 5)
          ├─ DualRing…（现有，最多 4）
          └─ WorkStatusSlot?   // 仅 work 启用时
```

- `AppDelegate.updateStatusItem` / `statusItemLength` 必须把 work slot 算进宽度（约 +36–44pt，实现时以实测不裁切为准）。
- 不新增第二个 `NSStatusItem`。
- `system` / `goals` 本切片仍不占栏。

---

## 6. 关键验收用例（给定 → 期望）


| # | 给定 | 期望 |
| --- | --- | --- |
| 1 | `enabledModules == {quota}`（work 关） | status 模型 / 视图 **无** work slot；长度与仅环一致 |
| 2 | 启用 `work`，`phase == .working`，剩余 focus = 12 分 5 秒 | slot 文案 `12:05` |
| 3 | 同上，tick 后剩余变为 12 分 4 秒 | 文案变为 `12:04`（秒级更新） |
| 4 | `phase` 从 `.working` → `.breakDue` | 文案变为 `BREAK`（不再是 `MM:SS`） |
| 5 | `phase == .breaking`，`breakRemaining` = 4 分 30 秒 | 文案 `04:30` |
| 6 | `phase == .breaking` → 结束后回到 `.working` | 文案回到剩余 focus `MM:SS` |
| 7 | 正在显示 work slot 时禁用 `work` | slot **立即消失**；仅剩环 |
| 8 | 再次启用 `work` | slot 重新出现，内容匹配当前 phase |
| 9 | 浅色 / 深色 Appearance | 文字对比度为 Mono 黑白灰（可读、无彩色 accent） |
| 10 | 整条 status item 点击 | 仍打开 popover（与现网相同；不因 slot 拆分手势） |

**边界：**


| # | 给定 | 期望 |
| --- | --- | --- |
| B1 | working 时 `workElapsed >= focusTarget`（即将/已到点） | 剩余显示 `00:00`，随后 phase 应进 `breakDue`（控制器既有行为） |
| B2 | `breakRemaining` 被夹到 0 | 文案 `00:00`，不出现负号 |

---

## 7. 验证策略

**原则：能抽纯函数的先测；人手只冒烟「像不像菜单栏产品」。**


| 层 | 本切片 | 谁跑 |
| --- | --- | --- |
| 单元（`swift test`） | `WorkStatusSlotModel`（或等价）：`(workEnabled, phase, focusRemaining, breakRemaining) → SlotContent?` | CI / agent / 本地 |
| 集成 | `StatusItemView` / `AppDelegate` 接线暂不自动化 | 单元绿 + 短冒烟 |
| UX | 宽度是否挤、BREAK 是否一眼可辨 | **仅你**：实现后 5 分钟 |

建议模型枚举（示意，实现可微调命名）：

```swift
enum WorkStatusSlotContent: Equatable {
    case focusRemaining(String)  // "MM:SS"
    case breakDue                // render as "BREAK"
    case breakRemaining(String)  // "MM:SS"
}

static func content(workEnabled: Bool, phase: …, …) -> WorkStatusSlotContent?
// workEnabled == false → nil
```

可放 `Sources/KajiCore/`（与 `ModulePrefsLogic` 同层）；时钟格式化可复用/下沉现有 `MM:SS` 规则。

手工冒烟（实现完成后）：

1. 默认仅 quota → 栏上无倒计时  
2. 开 work → 环旁出现 `MM:SS`  
3. 等到 breakDue → 变 `BREAK`  
4. 进入 break → 变 break 倒计时  
5. 关 work → 槽消失  
6. 浅/深色各看一眼对比度  

---

## 8. 完成条件（Definition of Done）

- [ ] §6 用例 1–10 与 B1–B2：纯模型有自动化；接线项有冒烟勾选
- [ ] `work` 关 ⇒ 菜单栏无 work 文案/占位
- [ ] `work` 开 ⇒ working / breakDue / breaking 三种呈现符合 §4
- [ ] 状态栏仍是单条 `NSStatusItem`，HStack 组合
- [ ] 无版本号变更、无 GitHub Release
- [ ] 维护者本地扫一眼：默认仍安静；开 work 后信息密度可接受

---

## 9. 风险


| 风险 | 缓解 |
| --- | --- |
| `BREAK` + 多 provider 环把菜单栏挤宽 | 限制环仍 `prefix(4)`；work 文案用窄字体/固定宽；必要时略减 spacing |
| 与 popover 内 elapsed「工作时钟」不一致 | 菜单栏明确是 **剩余**；popover 可继续显示 elapsed（本切片不强制改 popover） |
| `updateStatusItem` 漏订 phase/时钟 | 订阅 `workSession.$phase` 与已有秒级驱动，禁用时强制清槽 |
| 范围滑向重画 Break | 严格 Non-goals |

---

## 10. 文件触点（实现时，本切片不写代码）

| 区域 | 文件 |
| --- | --- |
| 纯模型 + 测试 | `Sources/KajiCore/`（新小文件）、`Tests/KajiTests/` |
| 视图组合 | `StatusItemView.swift` |
| 宽度 / 刷新 | `AppDelegate.swift` |
| 时钟/phase 源 | `WorkSessionController.swift`（尽量只读；格式化下沉 Core） |

---

## 11. 审稿状态

**Status: draft — 待审**

请审稿人确认三处拍板：剩余 focus（非 elapsed）、breakDue = `BREAK`、槽在环右侧。通过后：**测试 → 实现**，不另写 plan。
