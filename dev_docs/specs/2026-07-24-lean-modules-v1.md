# Spec: Lean Modules v1 — 可裁剪

> **Status:** approved（2026-07-24）  
> **Date:** 2026-07-24  
> **Branch:** `docs/lean-module-host`（实现时可再开 `feat/lean-modules-v1`）  
> **Ship:** 不发版、不涨版本号  
> **Upstream:** [product/lean-module-host.md](../product/lean-module-host.md)、[product/architecture-modules.md](../product/architecture-modules.md)、[AGENTS.md](../../AGENTS.md)

这份是 **可验收 feature spec**（定义「什么算对」）。  
对本切片：**不强制另写长 plan**；下一步按 §7 用例写测试，再实现（见 §9）。

---

## 1. 用户目标

让觉得「加戏太多」的用户，**不必回退版本**，就能把 Kaji 收成安静的用量工具；需要 Work / System / Goals 的人仍可自行打开。

一句话成功标准：

> 默认打开像早期小而美；多余模块能关掉且再也看不到。

## 2. 范围内（In）

1. 内置模块 ID：`quota` | `work` | `system` | `goals`
2. `Prefs.enabledModules` 持久化；Settings 里可开关
3. Popover 轮播 **只含已启用模块**（顺序固定：quota → work → system → goals，跳过未启用）
4. 默认瘦：仅 `quota` 开
5. 迁移：首次引入本功能时写入瘦默认（见 §6）
6. `quota` **不可关闭**（始终启用）
7. 关闭 `work`：停止 work session 计时；若正在 break overlay，立即 dismiss；Work 面板不再出现
8. 关闭 `system`：停止 system monitor 轮询；面板不出现
9. 关闭 `goals`：Goals 面板不出现（store 可懒加载/廉价保留，不要求物理删除数据）
10. 关闭不该再「漏」：已禁用模块不得出现在 popover 页码、标题、左右翻页循环里



## 3. 范围外（Non-goals）

本 spec **不做**：

- Work 倒计时挂到菜单栏（下一份 spec）
- 删除 Color / Calm / Playful 主题（下一份 Mono-only spec）
- 远程插件、商店、动态 bundle
- Ice / 管理其它 App 的菜单栏图标
- 重写 Break UI / 运动关卡 / 场景图（可继续存在于 `work` 开启时的现有路径）
- 改 README 营销文案、GitHub Release、版本号
- Pet 状态栏大件
- 拆 SPM 多 target 大重构（允许为测试加一个小 `KajiCore`/`KajiTests`，见 §9）



## 4. 模块表（本切片）


| ID       | 默认        | Popover     | 状态栏（本切片）     | 关闭时                         |
| -------- | --------- | ----------- | ------------ | --------------------------- |
| `quota`  | **开（强制）** | 用量面板        | 保持现有双环       | 不可关                         |
| `work`   | 关         | focus/break | 本切片不新增 glyph | 停计时 + dismiss overlay + 无面板 |
| `system` | 关         | 系统面板        | 无            | 停轮询 + 无面板                   |
| `goals`  | 关         | 目标面板        | 无            | 无面板                         |


**本切片拍板（原 product 待讨论）：**


| 议题      | 决定                                 | 理由                              |
| ------- | ---------------------------------- | ------------------------------- |
| Work 默认 | **关**                              | 最大程度回到「只有用量」；需要的人打开             |
| 老用户迁移   | **首次写入瘦默认（仅 quota）**               | 回退用户要的是变瘦；愿意全家桶的人可在 Settings 打开 |
| 重 Break | **仍挂在** `work` **下**；`work` 关则整条消失 | 不新开模块，避免加戏                      |




## 5. 行为说明



### 5.1 Settings

- 新增「Modules」区域（文案 EN/中文跟现有 L10n 风格）
- 四个开关；`quota` 开关禁用或打开后无法关掉（UI 上明确）
- 切换立即生效：若 popover 正打开，下一帧/下次构建只显示新集合；若当前页被关掉，落到仍启用的最近一页（优先 quota）



### 5.2 Popover

- 页集合 = `enabledModules` 按稳定顺序排序后的列表
- 仅 1 页时：隐藏左右箭头或禁用翻页（二选一，实现选更简单的；不得空转翻到已禁用页）
- 页码文案为 `i/n`，`n` = 启用数量



### 5.3 生命周期


| 事件          | 期望                          |
| ----------- | --------------------------- |
| 启用 `work`   | 可开始 focus/break；行为与现网一致     |
| 禁用 `work`   | 计时停；overlay 关；不再调度 breakDue |
| 启用 `system` | 开始/恢复 monitor               |
| 禁用 `system` | 停止 poll                     |
| 启用 `goals`  | 面板可见                        |
| 禁用 `goals`  | 面板不可见；不要求清历史                |




### 5.4 不变量

1. `enabledModules` 始终包含 `quota`
2. Popover 可见页集合 == 启用模块集合（顺序稳定）
3. 禁用模块的 UI 面与后台活动（就本表所列）必须停
4. 不引入新的默认开启表面



## 6. 迁移

- UserDefaults 新 key：例如 `enabledModules`（`[String]`）
- 另用 `enabledModulesMigrated`（Bool）或「key 不存在」判断首次
- **首次**：写入 `["quota"]`（瘦默认），即使老用户之前一直在用四面板
- **之后**：尊重用户改过的 `enabledModules`
- 本切片 **不做** 迁移 toast / onboarding（避免又加戏）；可在 Settings Modules 区用一行说明默认是 Quota only



## 7. 关键验收用例（人出题）

实现前，这些应先变成测试或手工清单上的断言。格式：给定 → 期望。


| #   | 给定                          | 期望                                 |
| --- | --------------------------- | ---------------------------------- |
| 1   | 全新 prefs / 首次迁移             | `enabledModules == {quota}`        |
| 2   | 首次迁移后打开 popover             | 只有 Quota 一页；无 Work/System/Goals    |
| 3   | 启用 `work`                   | popover 可翻到 Work；页码分母为 2           |
| 4   | 再启用 `system`、`goals`        | 四页都在；顺序 quota→work→system→goals    |
| 5   | 禁用 `work`（当时停在 Work 页）      | 落到仍启用的页（如 quota）；之后翻页永不出现 Work     |
| 6   | break overlay 显示中，禁用 `work` | overlay 立刻消失；session 不再处于 breaking |
| 7   | 尝试关闭 `quota`                | UI/Prefs 拒绝；集合仍含 quota             |
| 8   | 仅 quota 启用                  | 翻页不出现空页/闪其他模块                      |
| 9   | 禁用 `system`                 | monitor 轮询停止（可用测试替身或「无定时回调」断言）     |
| 10  | 进程重启后                       | `enabledModules` 与退出前一致            |


**边界 / 坏数据：**


| #   | 给定                              | 期望                |
| --- | ------------------------------- | ----------------- |
| B1  | UserDefaults 里是 `[]` 或损坏数据      | 回退为 `{quota}`     |
| B2  | 含未知 id `"foo"`                  | 忽略未知；仍保证含 `quota` |
| B3  | 仅有 `["work","system"]`（无 quota） | 加载时补上 `quota`     |




## 8. 性能 / 体验预算

- 开关切换后，popover 内容更新应在下一次 runloop 可见（无多秒延迟）
- 禁用 `system` /（若实现停 quota 脚本——本切片 **quota 不可关**，故恒跑）后，不应再为已关模块打日志刷屏
- 本切片不改菜单栏宽度逻辑，除非仅 quota 时与现网一致



## 9. 验证策略

**原则：开发阶段能稳定自动化的就自动化；人手只留给「像不像产品」的最终判断。**

| 层 | 本切片 | 谁跑 |
| --- | --- | --- |
| 单元（`swift test`） | `normalizeEnabledModules` / `popoverPages`（§7 规则与边界） | CI / agent / 你本地一条命令 |
| 集成 | Prefs ↔ UI 接线暂不单独自动化 | 实现后靠单元 + 短手工冒烟 |
| E2E / UX | 「默认是否小而美」、overlay 体感 | **仅你**：实现绿了之后 5 分钟冒烟 |

已落地：`Tests/KajiTests/ModulePrefsLogicTests.swift`（先红后绿）。

手工冒烟（实现完成后，不是开发中天天点）：

1. 迁移后默认几乎只有 Quota  
2. Settings 开关增减页  
3. break 中关 work → overlay 没了  
4. quota 关不掉  
5. 重启后 prefs 仍在  

## 10. 回滚

- 功能由 UserDefaults 驱动；若严重缺陷：回退 git 分支即可
- 不改 Release 资产；`main` 用户不受影响，直到显式合并
- 若合并后要紧急止血：可临时忽略 `enabledModules`、恢复四页硬编码（应避免；优先修 normalize）



## 11. 完成条件（Definition of Done）

- [ ] 用例 1–10 与 B1–B3 有自动化或手工勾选记录
- [ ] Settings 可开关；`quota` 关不掉
- [ ] 默认 / 迁移后体验为「几乎只有用量」
- [ ] 禁用 `work` 时 overlay 不会残留
- [ ] 无版本号变更、无 GitHub Release
- [ ] 你（维护者）本地用一天，不觉得比回退旧版更吵



## 12. 风险


| 风险               | 缓解                          |
| ---------------- | --------------------------- |
| 老用户升级后突然少面板，以为坏了 | Settings 说明 + 易找的开关；本切片不做弹窗 |
| Popover 大文件难测    | 逻辑抽纯函数，UI 手工                |
| 范围膨胀（顺手做倒计时上栏）   | 严格 Non-goals；另开 spec        |




## 13. 审稿结论

三处拍板已接受（2026-07-24）：瘦默认迁移、`quota` 强制常开、本切片不含状态栏倒计时。

**下一动作：** 按 §7 / §9 写测试 → 再实现。不另写 plan 文档。
