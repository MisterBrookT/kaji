# Spec: Cursor 用量环（quota provider）

> **Status:** approved（2026-07-24）  
> **Date:** 2026-07-24  
> **Branch:** `feat/cursor-quota`（或直接落 main 后打 `v0.6.1`）  
> **Ship:** **v0.6.1**（本切片验收通过后发版）  
> **Upstream:** 现有 `Resources/quota.py` + `Providers`；[AGENTS.md](../../AGENTS.md)

这份是 **可验收 feature spec**。  
目标：在 Kaji 里像 Claude / Codex 一样，用 **双环** 显示 Cursor 的当前计费周期用量。

**不做远程插件市场；不宣称官方 API。**

---

## 1. 用户目标

本机已登录 Cursor 的用户，在菜单栏 / popover **一眼看到** 当前周期还剩多少额度，不必打开 Cursor Settings → Usage。

一句话成功标准：

> 有 Cursor 登录态 → 默认出现 `Cursor` 用量环（与 Claude/Codex 同级）；无登录 / 拉失败 → 安静消失，不弹错、不写 token 进日志。

---

## 2. 调研结论（本机已验证，写入 spec 作约束）

| 项 | 结论 |
| --- | --- |
| 本地 usage 文件 | **无**（不像 Claude/Codex 的 5h/7d 本地缓存） |
| Token | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` → `ItemTable.key = 'cursorAuth/accessToken'` |
| API | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| Headers | `Authorization: Bearer <token>` · `Connect-Protocol-Version: 1` · `Content-Type: application/json` · body `{}` |
| 形状（实测） | 月度池：`autoPercentUsed` / `apiPercentUsed` / `totalPercentUsed`；`billingCycleStart` / `billingCycleEnd`（epoch **ms**） |
| 稳定性 | **非公开契约**；字段名或路径变更时允许静默失败 |

样例字段（数值会变；**嵌套 `planUsage` 为 2026-07 实测**，扁平根字段作兼容）：

```json
{
  "billingCycleStart": "1784702421000",
  "billingCycleEnd": "1787380821000",
  "planUsage": {
    "autoPercentUsed": 39.5,
    "apiPercentUsed": 100,
    "totalPercentUsed": 47.4
  }
}
```

映射时：优先 `planUsage.*PercentUsed`，否则回退根级同名字段；`billingCycleEnd` 可为 number 或 digit string（epoch ms）。

---

## 3. 范围内（In）

1. `quota.py` 增加 **Cursor limits fetch**（读 sqlite token → POST → 映射为现有 `*_used_percent` / `*_resets_at` 形状）
2. `collect()` 输出一行 `provider: "cursor"`（有 token 且 fetch/缓存成功时）
3. `Providers`：`cursor` 进入 `available` **与** `visible`（与 Claude/Codex 同级默认可见）；展示名 `Cursor`；排序在 `claude` 后
4. **默认可见性：** **默认开**（进 `Providers.visible`）。升级用户做一次迁移：把 `cursor` 插入已保存的 `visibleProviders`（仅一次；之后用户关掉不再强行加回）
5. Popover / RingGauge 对 `cursor`：**不用**「5h / 7d」文案，改用 **API / Auto**（对齐环几何，见 §5.2）
6. 磁盘缓存：复用 `_limits_cached`（TTL ≈ 180s）
7. 隐私：token **仅进程内使用**；不写进 Kaji 支持目录明文；日志 / stderr 不打印 token
8. **limits-only：** 不扫本地 transcript、不估「今日 token」；JSON **省略** `tokens_today` / `cost`（或显式 `null`），**不要**写 `0` 假装有统计
9. Popover 对 Cursor：**只展示限额环相关**（API/Auto %、reset）；行内不显示今日 token / cost；不画 token sparkline
10. 顶部 Today / Cost 汇总：**只加总真正有今日用量的 provider**（Claude/Codex…）；Cursor 不贡献
11. 纯映射 / 标签逻辑可测（clamp、ms→ISO、缺字段跳过、窗标签）

## 4. 范围外（Non-goals）

- 官方 Cursor SDK / 文档化 API 承诺
- 解析 Cursor chat / composer 本地文件估今日 token / sessions / 24h 曲线（见 §5.5–5.6）
- 第二个菜单栏 icon、远程插件、README 营销大改
- Pro / Ultra 策略教学、spend 美元明细 UI
- Windows / Linux Cursor 路径
- 改 lean 模块开关模型（Cursor 是 **provider**，不是 `enabledModules`）
- 把顶部 Pressure 副文案「5h max」改成动态文案（可后续；本切片可仍显示 5h max，数字用外环 %）

---

## 5. 行为表

### 5.1 数据何时出现

| 条件 | `quota.py` 行为 |
| --- | --- |
| 无 `state.vscdb` / 无 `cursorAuth/accessToken` | **不** emit `cursor` 行 |
| 有 token，HTTP 2xx + 可解析百分比 | emit `cursor` + limits（无今日 token） |
| 有 token，401/403 | 不 emit（或无 limits）；**不**弹系统告警 |
| 有 token，5xx / 超时 / 字段消失 | 用缓存（若有）；否则不 emit / 无 limits |
| DB 被 Cursor 锁住读失败 | 同失败路径；不崩溃 Kaji |

### 5.2 双环映射（已拍板）

Kaji 环几何（`RingGauge` / `DualRing`）：

- **外环** ← `five_hour_*`
- **内环** ← `seven_day_*`

用户拍板：**外 API / 内 Auto**。因此：

| Kaji 字段 | Cursor 源 | UI 标签（仅 cursor） | 环 |
| --- | --- | --- | --- |
| `five_hour_used_percent` | `apiPercentUsed` | **API** | **外** |
| `seven_day_used_percent` | `autoPercentUsed` | **Auto** | **内** |
| 两窗 `*_resets_at` | 均用 `billingCycleEnd`（ms → ISO-8601 UTC） | Reset 沿用现有 | — |

`totalPercentUsed` 本切片不占环。

### 5.3 UI / Settings

| 面 | 行为 |
| --- | --- |
| Settings → Providers | `Cursor` 与 Claude/Codex 同级列出 |
| 默认 | **开**（在 `visible`） |
| 升级迁移 | 一次插入 `cursor`；用户关掉后尊重偏好 |
| Popover / 环文案 | **API / Auto**，不是 5h/7d |
| 菜单栏环 | 有 limits 就画双环（与 Claude 一样靠 %） |

### 5.4 Logo

- Unicode / 现有 `ProviderLogo` 占位即可；不阻塞。

### 5.5 为何做不到可靠的「今日 / 24h token」（结论）

Kaji 里 Claude/Codex 的 **Today tokens / Cost / sparkline** 来自扫本机 chat 日志，和账号限额环是两条线。

Cursor：

| 想要的 | 有没有 |
| --- | --- |
| 计费周期 Auto/API % | 有（本切片用的 API） |
| 今日用了多少 token | **API 不给** |
| 本机可加总的 usage 文件 | **没有**（不像 `~/.claude/projects/**/*.jsonl`） |
| 可信的 24h 估计 | **本切片做不到**（翻私有 DB/transcript 脆、未文档、还可能和仪表盘对不上） |

所以：**不是「先估一个假数」**，而是 **承认没有今日量，UI 不假装有**。

### 5.6 Popover「今日用量」怎么办（已拍板）

对照 Quota 页：

| 表面 | Claude/Codex | Cursor（本切片） |
| --- | --- | --- |
| 顶部 **Today** / **Cost** | 有今日 token 才计入汇总 | **不计入**（缺数据 ≠ 0） |
| 顶部 **Pressure** | 外环 % 最大值 | Cursor 的 **API %** 可参与 max |
| 行内 `53.6M · $12.67 est` | 显示 | **不显示**（安静省略，不用 `—` 占位） |
| 行内 5h/7d 文案 | 5h / 7d | **API / Auto** + reset |
| 底部 sparkline | token 历史 | **不画** |
| 行首大 % | 外环 used % | 仍显示 **API %** |

错误做法（明确禁止）：

- 写 `tokens_today: 0` 导致 Today 被污染或行内冒出 `0` / `$0.00 est`
- 用周期 % **冒充** 今日 token

若以后 Cursor 露出稳定的今日用量源，另开 spec 再补。

---

## 6. 可验收用例

| # | 给定 | 期望 |
| --- | --- | --- |
| 1 | 本机有 Cursor token，fetch 成功，`api=100` `auto=38` | quota JSON 含 `cursor`；外=`api`、内=`auto`（容差 0.5） |
| 2 | 无 token | 输出 **无** `cursor` 行 |
| 3 | token 无效 401 | 无崩溃；无 token 泄露；无 `cursor` 或无 limits |
| 4 | 缓存未过期再次 collect | 不狂打 API |
| 5 | 新装 / 升级默认 | Cursor **在** `visible`（菜单栏可出现，受 max 4 截断） |
| 6 | 有 limits 时 | 环标签；文案 API/Auto 而非 5h/7d |
| 7 | `billingCycleEnd` 在未来 | Reset 文案合理 |
| 8 | Light / Dark | Mono 环可读 |
| 9 | 用户关掉 Cursor provider | 环消失；重启仍关 |
| 10 | Cursor 行 | **无**今日 token / cost 文案；**无** sparkline |
| 11 | 顶部 Today/Cost | 仅含有今日量的源；Cursor 不贡献 0 |

**边界：**

| # | 给定 | 期望 |
| --- | --- | --- |
| B1 | 只返回其一百分比 | 仅对应环有值 |
| B2 | 百分比 > 100 或 < 0 | 夹到 `[0, 100]` |
| B3 | 非默认 Application Support 路径 | 本切片不支持 |

---

## 7. 验证策略

| 层 | 本切片 |
| --- | --- |
| 单元 | `CursorLimitsLogic`：映射 + clamp + reset；窗标签 API/Auto |
| 集成（可选） | 本机真 token 跑 `quota.py --json`（不把 token 写进夹具） |
| UX 冒烟 | 默认见 Cursor 环（有登录时）；标签正确；关掉仍关 |

---

## 8. 实现草图（非 plan）

| 触点 | 改动 |
| --- | --- |
| `Resources/quota.py` | token · fetch · map · `collect()` |
| `Sources/KajiCore/CursorLimitsLogic.swift` | 映射 + 标签 |
| `Sources/Kaji/Providers.swift` | marks / names / order / visible / available |
| `Sources/Kaji/Prefs.swift` | 一次升级插入 `cursor` |
| `RingGauge` / `KajiPopoverView` / `GaugeRowView` | 按 provider 取窗标签 |
| `Tests/…` | 映射与标签 |
| `Info.plist` + `dev_docs/ship/releases/v0.6.1.md` | 发版 |

---

## 9. 风险

| 风险 | 缓解 |
| --- | --- |
| API 无预告变更 | 失败静默；缓存；unofficial |
| sqlite 锁 | 短超时；失败当未配置 |
| 环语义与 5h/7d 混淆 | 强制 API/Auto 标签 |
| 默认开导致菜单栏更挤 | 仍受 prefix(4)；用户可关 |

---

## 10. 已拍板 / 待点头

| # | 决定 |
| --- | --- |
| 1 | 外 API / 内 Auto（`five_hour`←api，`seven_day`←auto） |
| 2 | 默认可见，与 Claude/Codex 同级 |
| 3 | **limits-only**；不做估今日 / 24h token |
| 4 | Ship **v0.6.1** |
| 5 | Popover §5.6 — **有环、无今日列**（安静省略；不用 `—`） |

---

## 11. 完成定义

- [x] 拍板已定  
- [x] Status → **approved**  
- [x] 实现：§6 用例绿 + 本机冒烟  
- [ ] 打 `v0.6.1` 发版
