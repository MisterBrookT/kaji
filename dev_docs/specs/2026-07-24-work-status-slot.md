# Spec: Work Status Slot — 菜单栏倒计时槽

> **Status:** approved（2026-07-24）  
> **Date:** 2026-07-24  
> **Branch:** `docs/lean-module-host`（实现时可再开 `feat/work-status-slot`）  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [specs/2026-07-24-lean-modules-v1.md](./2026-07-24-lean-modules-v1.md)（已通过）、[product/lean-module-host.md](../product/lean-module-host.md)、[product/architecture-modules.md](../product/architecture-modules.md)、[AGENTS.md](../../AGENTS.md)

这份是 **可验收 feature spec**。  
lean-modules-v1 已落地（`enabledModules`、瘦默认、popover 过滤）。本切片补上：**可组合状态栏槽位**。

对本切片：**不强制另写 plan**；下一步按 §6 用例写纯逻辑测试，再接线 UI。

---

## 1. 用户目标

启用 `work` 时，在菜单栏 **一眼看到** 当前 focus / break 还剩多久，不必打开 popover。

一句话成功标准：

> Work 开 = 环旁有紧凑倒计时；Work 关 = 菜单栏仍只有用量环（安静）。

---

## 2. 范围内（In）

1. 当 `prefs.isModuleEnabled(.work)` 为真时，`StatusItemView` 在用量环右侧增加 **work status slot**
2. 槽位内容随 session 时钟更新（约 1s）
3. 可组合布局：`HStack` = quota rings + 可选 work slot
4. `work` 关闭时：不渲染 work slot；宽度回到仅环
5. 视觉：Mono / blackWhite；不引入彩色 glyph
6. 纯展示模型抽到 `KajiCore`（便于 `swift test`）

## 3. 范围外（Non-goals）

- Ice / 其它 App 图标管理
- 新模块、插件、发版、README 营销大改
- 重写 Break overlay（现有全屏倒计时路径保持；本切片只加菜单栏数字）
- System / Goals 状态栏 glyph
- Mono-only 清 Color 债（另 spec）
- 槽位独立点击手势（整条 status item 仍开 popover）
- 菜单栏单独的 `BREAK` 文案 cue（已否决）

---

## 4. 行为表

**用户能感知的只有两种倒计时**（与全屏 overlay 对齐）：

| 条件 | 菜单栏 work slot |
| --- | --- |
| `work` **未启用** | **无槽** |
| `work` 启用 · 专注中（`working`） | **剩余 focus** `MM:SS` |
| `work` 启用 · 休息中（`breaking`） | **剩余 break** `MM:SS`（通常同时有全屏 overlay） |
| `work` 启用 · 内部 `breakDue` | **按休息剩余显示** `MM:SS`（与 `breaking` 同形；见下） |
| 样式 | Mono；约 11–12pt；不抢环 |
| 更新 | 秒级刷新 |

### 关于 `breakDue`（实现细节，不是第三种 UX）

代码里仍有 `WorkSessionPhase.breakDue`：计时器到点后的**内部信号**。  
`AppDelegate` 会立刻 `startBreak()` 并（若 Hard Break 开）弹全屏——用户几乎不会停在 breakDue。

因此菜单栏 **不** 为 breakDue 单独做 `BREAK` 文案。模型规则：

- `working` → focus 剩余  
- `breakDue` **或** `breaking` → break 剩余（`breakRemaining` / `breakClock`）

全屏 overlay 仍由现有 Hard Break 路径负责，本切片不改其产品行为。

**拍板：**

| 议题 | 决定 |
| --- | --- |
| working | **剩余** focus `MM:SS`（非 elapsed） |
| 休息相关 phase | 一律 break 剩余 `MM:SS`；无 `BREAK` 字 |
| 槽位位置 | 环 **右侧** |

---

## 5. 布局

```text
NSStatusItem
  └─ StatusItemView
        HStack(spacing ≈ 5)
          ├─ DualRing…（现有，最多 4）
          └─ WorkStatusSlot?   // 仅 work 启用时 → "MM:SS"
```

- `statusItemLength` 计入 work slot（约 +36–44pt，实测为准）
- 不新增第二个 `NSStatusItem`

---

## 6. 关键验收用例


| # | 给定 | 期望 |
| --- | --- | --- |
| 1 | work 关 | **无** work slot |
| 2 | work 开，`working`，剩余 focus = 12:05 | 文案 `12:05` |
| 3 | tick → 剩余 12:04 | 文案 `12:04` |
| 4 | `breaking`，`breakRemaining` = 4:30 | 文案 `04:30` |
| 5 | `breakDue`（若模型收到） | 文案为 break 剩余 `MM:SS`，**不是** `BREAK` |
| 6 | 休息结束 → `working` | 回到 focus 剩余 |
| 7 | 显示中禁用 `work` | slot 立即消失 |
| 8 | 再启用 `work` | slot 恢复，匹配当前 phase |
| 9 | Light / Dark | Mono 对比度可读 |
| 10 | 点击整条 status item | 仍开 popover |

**边界：**

| # | 给定 | 期望 |
| --- | --- | --- |
| B1 | focus 剩余夹到 0 | `00:00` |
| B2 | break 剩余夹到 0 | `00:00`，无负号 |

---

## 7. 验证策略

| 层 | 本切片 |
| --- | --- |
| 单元 | `WorkStatusSlotModel`：`(workEnabled, phase, focusRemaining, breakRemaining) → String?` |
| UX 冒烟 | 开 work 看数字；进休息看数字 + 全屏仍在；关 work 槽消失 |

```swift
// workEnabled == false → nil
// working → focus MM:SS
// breakDue | breaking → break MM:SS
static func label(...) -> String?
```

手工冒烟：

1. 默认无倒计时  
2. 开 work → `MM:SS`  
3. 进休息 → break `MM:SS`（全屏仍弹，若 Hard Break 开）  
4. 关 work → 槽没了  

---

## 8. 完成条件

- [ ] §6 自动化 + 冒烟勾选  
- [ ] work 关 ⇒ 无槽；开 ⇒ 仅两种数字态  
- [ ] 无 `BREAK` 文案  
- [ ] 单 `NSStatusItem` HStack  
- [ ] 不发版  

---

## 9. 风险

| 风险 | 缓解 |
| --- | --- |
| 多环 + 倒计时偏宽 | 环仍 cap 4；窄字重 |
| 与 popover elapsed 不一致 | 菜单栏明确是**剩余**；本切片不改 popover |
| 漏订 phase/时钟 | 订阅 workSession；禁用清槽 |

---

## 10. 文件触点

| 区域 | 文件 |
| --- | --- |
| 模型 + 测试 | `Sources/KajiCore/`、`Tests/KajiTests/` |
| 视图 | `StatusItemView.swift` |
| 宽度 / 刷新 | `AppDelegate.swift` |
| phase 源 | `WorkSessionController.swift`（只读） |

---

## 11. 审稿结论

已通过（2026-07-24）：剩余 focus / 剩余 break 两种数字；**不要** breakDue=`BREAK`；槽在环右侧。  
`breakDue` 仅内部信号，菜单栏与 `breaking` 同形。

**下一动作：** 测试 → 实现。不另写 plan。
