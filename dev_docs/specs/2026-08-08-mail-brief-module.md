# Feature Spec：Mail Brief Module

> 状态：Approved（2026-08-08；2026-08-14 增补执行模型设置）  
> PRD：[2026-08-08-mail-brief-prd.md](../product/2026-08-08-mail-brief-prd.md)  
> ADR：[2026-08-08-mail-brief-executor-adr.md](../product/2026-08-08-mail-brief-executor-adr.md)

## 类型

Primary: new feature  
Secondary: Gmail integration、AI execution、privacy、daily scheduler、module lifecycle、Goals integration

## Goal

为 Kaji 增加默认关闭的 Mail Brief module，每天一次将 Gmail Inbox 压缩为可扫视的行动列表，并让用户打开 Gmail、归档、置顶、移入 Trash、仅从简报忽略，或转成 Today Goal。

## In

- `KajiModuleID.mailBrief`，稳定页序放在 AI News 之后。
- Settings 中的 module 开关、Gmail Connect/Disconnect、每日本地时间和低权重“立即生成”。
- 单 Gmail 账号、Installed App OAuth + PKCE、按需升级到 Gmail modify scope、Keychain token。
- 每天一次与睡眠/关机后的当天补跑；同日幂等。
- headless Codex：用户可从受控列表选择模型，默认 `gpt-5.3-codex-spark`；reasoning 固定 `low`，输出使用 strict JSON schema。
- Act / Watch / Quiet 分类、解释理由、建议动作、deadline 与 confidence。
- 一级按 Level 分区、区头三块深浅灰重要度、hover 二级完整摘要。
- 菜单栏真实 Act 数量；无 Act 时只显示 glyph。
- 打开 Gmail、归档/撤销、置顶/取消置顶、移入/移出 Trash、转 Today Goal、仅从今日 Kaji 简报忽略/恢复。
- versioned local cache、stale/error/disconnected/running/quiet states。
- Mono Light/Dark 与四语言 Kaji chrome。

## Non-goals

- 不做 Inbox 阅读器、实时监听、通知、搜索、文件夹或通用标签管理；完整 Inbox snapshot 仅用于分类守恒与逐条 triage。
- 不发送、回复、永久清空 Trash、标记已读、snooze 或取消订阅 Gmail。
- 不生成可直接发送的回复草稿。
- 不支持 Outlook、IMAP、多 Gmail 账号或附件正文。
- 不建立长期联系人画像或自动学习优先级。
- 不复用 Lisa daemon，不安装 Mail launch daemon。
- 不提供任意 model ID、provider 或 reasoning effort 输入；模型只能从 Kaji 验证过的受控列表选择。
- 不把完整邮件正文写入长期 cache。

## Module 与 Settings

### 默认与生命周期

- 新旧用户升级后 `mailBrief` 均默认 Off。
- Off 时 page、status slot、timer、OAuth refresh、Gmail request 与 Codex process 全部不存在或停止。
- 开启但未连接时进入 Disconnected，不自动弹浏览器。
- 关闭 module 不自动撤销 OAuth；Disconnect 才删除 Keychain token。

### Settings

Mail Brief block 只包含：

- Module On/Off。
- Gmail：Connect / 当前账号 / Disconnect。
- Daily time，默认当前时区 `09:00`。
- `立即生成`，始终可见但低权重；未连接或正在运行时禁用。
- Batch size：允许 5 / 10 / 20 / 50 / 100，默认 10；从下一次 generation 生效。
- Concurrency：允许 1...4，默认 2；限制同时运行的 Codex batches。
- Model：允许 `GPT-5.3-Codex-Spark` 与 `GPT-5.6 Luna`，默认 Spark；UI 显示产品名，不允许自由输入 model ID。
- 最后成功时间与简短错误状态。

不显示 prompt、reasoning effort、token、Gmail query 或其他高级调参。

模型切换合同：

- 新选择从下一次 generation 生效，不中途替换正在运行的 batch。
- 模型属于分类缓存 identity。切换模型后，下一次 generation 明确重新分类当前 Inbox；普通刷新仍只分类新增或变化的 threads。
- checkpoint 记录 model ID；不同模型的 checkpoint 不得混合续跑。
- Spark 是 research preview，可能不可用、排队或触发独立限额。失败时保留旧简报并显示可操作错误，不得静默切换到 Luna。

## Gmail OAuth 与读取合同

- 系统默认浏览器打开 Google Authorization Code + PKCE。
- callback server 只绑定 `127.0.0.1` 随机端口，收到一次有效 state/code 后关闭。
- 校验 OAuth `state`；拒绝超时、重复、来源不匹配与缺 code 回调。
- Keychain item 以 Kaji bundle/service + Google subject 为 identity；日志只允许脱敏状态。
- 当前只读 credential 可继续展示简报；第一次使用 Archive、Flag 或 Delete 前，明确解释用途并要求用户重新授权 `gmail.modify`。不得静默失败或把只读 token 当作已升级。
- 升级后 scope 不得超过 identity 与 `gmail.modify`；不同时申请 `gmail.send`、`gmail.compose`。发送能力必须另案获批并再次增量授权。
- scope、授权账号与 capability 写入 credential metadata；UI 依据真实 capability 启用动作，不能只根据“已连接”推断可修改。
- Disconnect 撤销本地 token；远端 revoke 可 best-effort，失败不保留本地 credential。

候选读取：

- 只读取 Inbox，排除 Spam 与 Trash；已归档 thread 不再进入后续每日简报。
- 计数单位固定为 Gmail thread，而不是 message 或 unread badge。完整 generation 必须满足 `Act + Watch + Quiet = snapshotInboxThreadCount`。Archive 或 Delete 成功后，thread 与 snapshot Inbox total 同时减一；撤销后同时加一。Kaji-only ignore 仍属于原 bucket 并计入等式，只折叠其 row。
- 首次同步分页枚举当前全部 Inbox thread IDs，并读取、分类全部 threads；不得以最近 72 小时作为隐式覆盖边界。
- 后续优先使用 Gmail history cursor/稳定 fingerprint 找到新增、变化、归档与移回 Inbox 的 threads，复用未变化 thread 的既有结构化分类；至少每 7 天做一次全量 Inbox ID reconciliation。
- 每次 Codex invocation 最多 100 threads，整体输入仍遵守 300,000 字符上限；需要时连续执行多个 batch，直到覆盖整个 snapshot。`100` 不是每日上限。
- 同步中保存可恢复 checkpoint，失败项不计完成；UI 显示 `已分类 X / Inbox Y`。只有全部 thread 获得有效分类或安全 Watch fallback 后才原子发布完整 generation。
- thread 只保留参与人显示名/地址、subject、时间与裁剪后的纯文本消息序列；HTML 转纯文本，引用历史和签名可裁剪。
- 单 thread 模型输入最多 20,000 字符，整体输入最多 300,000 字符；截断必须标记 `wasTruncated`。
- 附件仅传文件名与 MIME type，不下载正文。

具体 Gmail REST endpoint 与 DTO 可由实现选择，但 tests 必须使用 stub，禁止访问真实账号。

## Daily scheduler

`MailBriefSchedulePolicy` 放入 KajiCore，输入 clock/timezone/config/last generation，输出：

- 今天是否 due。
- 下一次 due date。
- 是否属于补跑。

规则：

- 每个本地 `briefDay` 最多一次自动成功 generation。
- Kaji 启动、activation、wake、时间设置或时区变化时重新计算；不做分钟级轮询。
- 用单个可取消 timer 等待 due time。
- due 时已有运行则不并发。
- 自动失败不在当天循环重试；用户可点“立即生成”。
- 手动生成成功产生新的 generationID 并原子替换当天结果。
- 时区变化不允许在同一绝对 12 小时内产生两次自动 generation；边界算法必须单测。

## Codex executor

新增可注入 `MailBriefExecutor` protocol；生产 adapter 启动 `codex exec`，参数遵循 ADR。

executor 从 Settings 接收经过 allowlist 校验的 model ID；未知或已移除的持久化值回落到当前默认 Spark，但必须在运行前反映到 UI。reasoning effort 仍固定为 `low`。

输入 envelope 至少包含：

```text
schemaVersion
briefDay
locale
threads[]: id, subject, participants, messages, gmailSignals, wasTruncated
```

输出每个已分析 thread 恰好一项：

```text
threadID
level: 0...3
bucket: act | watch | quiet
summaryZH
reasonZH
suggestedAction: reply | createGoal | watch | none
deadline: ISO-8601 nullable
confidence: low | medium | high
goalTitleZH: nullable
```

约束：

- level 3 为最高优先，level 0 为 Quiet；低 confidence 不得进入 Quiet，归入 Watch。
- 模型不可新增未知 thread ID、遗漏输入 thread 或输出自由文本 wrapper。
- summary/reason/goalTitle 有明确长度上限；控制字符和 Markdown command 按普通文本处理。
- 一个条目语义失败可降级为 Watch fallback；整个 JSON/schema 失败则保留旧 generation。
- process timeout 初版 10 分钟；module 关闭或 app terminate 时先 terminate，宽限后强制结束。
- stdout/stderr 只保留脱敏 exit diagnostics，不进入普通 UI，不记录 prompt/result 正文。

## 持久化模型

Application Support 私有目录保存 `mail-brief-cache-v1.json`，atomic replace。至少包含：

- schemaVersion、generationID、briefDay、createdAt、lastSuccessfulGmailWatermark。
- account stable subject hash，不保存 access token。
- structured entries。
- 当前 generation 的 dismissed thread IDs 与 converted Goal IDs。
- snapshot Inbox thread count、sync cursor/checkpoint、last reconciliation time 与 last non-sensitive error code。

原始邮件正文不得进入此文件。损坏 cache 移到诊断副本后回到安全空状态，不崩溃。

只保留最近 7 个成功 brief 的结构化数据；启动时清理更老 generation 和遗留 temp 目录。Disconnect 默认保留简报，UI 提供明确“同时删除本地简报”选择。

## Level 分区标题

一级页面像 Goals 的 Today / Week 一样按 Level 划分区域。每个区域标题绘制三个 4–5pt 圆角实心方块，间距 2–3pt；邮件行本身不绘制方块：

- 激活位：当前主题下较深的 Mono gray。
- 非激活位：当前主题下较浅的 Mono gray。
- 不使用白色、透明空心、描边、红黄绿或动画。
- level 3 = 3 深；level 2 = 2 深 + 1 浅；level 1 = 1 深 + 2 浅；level 0 = 3 浅。
- accessibility label 使用文字“最高优先 / 重要 / 留意 / 安静”，不让 VoiceOver 读“方块”。

这组方块表示整个区域的重要度，不表示完成度。不能复用 Goals checkbox/progress 的语义状态，也不得在区内每封邮件旁重复绘制。

## 一级 popover

沿用 Kaji 现有 page shell 和 AI News scroll/hover 交互。

排序与分区：

1. Level 3、Level 2、Level 1 分别形成独立区域，按重要度从高到低排列；空区域不显示。
2. Act 全部展示，不做人为数量截断；同区域按 deadline、最近变化排序。
3. Level 0 / Quiet 默认折叠，只显示数量；用户展开后可查看。
4. 已归档默认进入“已完成”折叠区，已移入 Trash 默认进入“已删除”折叠区，两者当天均可撤销；仅本地忽略的条目进入“已忽略”折叠区，当天可恢复。

每个区头包含 Level 方块、可理解的文字标题与条目数。每行只包含最多两行标题、可用时低权重发件人，以及 Archive、Flag、Delete、`转 Goal`。仅本地忽略放入次级菜单。垃圾桶图标只表示真实 Move to Trash，不再表示 Kaji-only ignore。按钮有 tooltip/accessibility label；不能依赖 hover 才可操作。

### Gmail triage actions

- `完成` 是用户明确动作，不因打开邮件、hover、转 Goal 或摘要生成而自动触发。它调用 Gmail thread modify，移除 `INBOX` label；不标记已读、不删除邮件。
- Gmail 归档成功后，条目才从主分区移到当天“已完成”。API 失败时条目留在原位并显示可重试错误，不制造本地成功假象。
- “已完成”中的撤销为 thread 恢复 `INBOX` label；成功后回到原 Level 排序。撤销失败则仍保留完成态并显示错误。
- `置顶` 对应 Gmail `STARRED` label（即 Gmail 星标/其他客户端常称 Flag），不是 Kaji 私有排序。再次点击取消星标；状态在当前 UI 即时更新，并由下次 fetch 与 Gmail 服务端校准。
- 置顶不会归档，也不会改变 Level；排序时同 Level 的 starred 优先。不能把 Priority/Important label 当作置顶。
- `删除` 调用 Gmail thread trash，将整条 thread 移入 Trash；不调用永久 delete。成功后进入当天“已删除”，撤销调用 untrash 并回到 Inbox 原 Level 排序。
- Archive 与 Delete 均不二次确认，以当天折叠区内的撤销作为恢复路径。API 失败时仍留在原分区，不显示假成功。
- API 操作按 thread 执行并具有幂等性：重复 add/remove 同一 label 或重复 trash/untrash 得到同一结果；运行中禁用该条目的重复动作。
- `忽略本次简报` 只写本地 dismissed set，立即移入“已忽略”，不修改 Gmail；当天可恢复。下一次每日简报仍可重新判断。
- Gmail 写动作不得 optimistic commit；允许短暂 busy 状态，但服务端成功前菜单栏 Act 数量与本地 cache 不改变。

`转 Goal`：

- 用户点击后直接创建 Today Goal，标题优先用模型 `goalTitleZH`，否则用邮件 subject。
- Goal note 保存摘要、建议动作与 Gmail deep link；不得保存完整正文。
- 同一 generation/thread 重复点击不创建第二个 Goal，按钮改为已转换状态，并可跳转 Goals。

## Hover 二级 popover

- 约 180–250ms 后出现；一级与二级联合区域约 220ms 后关闭。
- 相邻 row 切换沿用 AI News generation/debounce，不能先闪旧内容。
- 显示 sender、subject、1–2 句摘要、重要原因、建议动作、deadline 与“在 Gmail 打开”。
- 鼠标可进入二级且保持打开，同时只显示一项。
- 没有有效摘要时显示安全 fallback，一级仍可使用。
- 不显示完整正文，不继续产生第三层 popover。

## Menu bar

- module Off：slot 为 nil，不占宽度。
- module On：独立 Mono mail glyph；未 dismiss Act > 0 时显示真实十进制数量，不截成 `3+`。
- 0 Act 时只显示 glyph，不显示 0、红点或通知。
- 数量可增长，但使用 compact monospaced digits；status width 按实际内容计算，不裁掉两位及以上数字。
- 点击直达 Mail Brief page；在当前 page 时沿用现有关闭行为。

## States

| State | UI |
| --- | --- |
| Disconnected | 简短说明 + Connect Gmail |
| Scheduled | 今日未到时间；显示下次时间 |
| Running | 保留旧结果，低权重处理中 |
| Initial sync | 无旧结果时显示“已分类 X / Inbox Y”；不能同时显示 Quiet day |
| Ready | Act / Watch 列表、Quiet/已移除折叠区、更新时间 |
| Quiet day | 没有 Act/Watch，明确说明今天无需处理 |
| Stale | 保留旧结果 + 最后成功时间 + 简短错误 |
| Failed no cache | setup/retry，不倾倒 CLI/Gmail 日志 |
| Disabled | page/slot/timer/request/process 全无 |

## Privacy 与安全

- OAuth 前明确写明：邮件正文会发送到用户登录的 Codex 云端分析。
- Gmail token 只进 Keychain/Gmail client，不进模型、cache、argv、日志。
- 邮件内容全视为 prompt injection 数据，不执行其中命令、链接或工具请求。
- Codex 在随机临时目录、read-only sandbox、ephemeral session、ignored config/rules 下运行。
- Kaji 不读取用户 Codex credential，只观察 CLI 成功/失败。
- UI 和日志不得显示完整地址列表、正文、token、authorization code 或 refresh token。

## Acceptance

| ID | Given | Expected | Verify |
| --- | --- | --- | --- |
| M1 | 旧 prefs 无 Mail Brief | 默认 Off，现有 modules/page order 不变 | unit |
| M2 | module Off | page/slot/timer/Gmail/Codex 全部停止 | unit + human |
| O1 | OAuth success | PKCE/state 校验，token 只进 Keychain，loopback listener 关闭 | unit + integration |
| O2 | OAuth cancel/invalid callback | 不保存 credential，不崩溃，可重试 | unit |
| O3 | Disconnect | 本地 token 删除，后续不 fetch | unit + human |
| O4 | 只读 credential 点击 Gmail 写动作 | 解释用途并重新授权 `gmail.modify`；授权取消则不修改 Gmail 或本地状态 | unit + integration |
| G1 | 首次 fetch | 分页覆盖当前全部 Inbox threads，排除 Spam/Trash，不下载附件正文 | unit |
| G2 | 后续 fetch | cursor/fingerprint 只重算变化项，并通过 reconciliation 不漏 thread | unit |
| G3 | Inbox 超过 100 threads | 分成多个 Codex batch，失败 batch 可恢复；最终无静默遗漏 | unit + integration |
| G4 | 完整 snapshot 发布 | Act + Watch + Quiet 严格等于 Inbox thread 总数；不拿 Gmail unread badge 比较 | unit + human |
| G5 | 首次同步未完成 | 显示已分类 X / Inbox Y，不显示 Quiet day 或伪完整结果 | unit + human |
| D1 | 到 09:00 且今日未成功 | 只启动一次自动 generation | unit |
| D2 | 睡眠错过 09:00 | 当天 activation 补跑一次 | unit |
| D3 | 同日重复 activation/并发事件 | 不产生重复自动 run | unit |
| D4 | 时区/DST 边界 | 不在 12h 内双跑，next due 正确 | unit |
| E1 | executor invocation | 所选 allowlisted model + low + read-only/ephemeral/isolated flags 正确，prompt 走 stdin | unit |
| E2 | model switch | 下一轮重分类全 Inbox；不同 model checkpoint 不混用；失败不静默 fallback | unit + integration |
| E2 | valid schema result | 每个 thread 映射成功并原子保存 | unit |
| E3 | prompt injection text | 只作正文，不触发工具/格式改变 | fixture + integration |
| E4 | timeout/nonzero/bad schema | 旧结果保留，temp 清理，显示安全错误 | unit + integration |
| P1 | level 0...3 区域 | 每个非空 Level 独立成区；区头三个位置均为灰色实心块且深灰数量准确；邮件行没有方块 | snapshot + human |
| P2 | VoiceOver | 区头读重要度文字，不逐块朗读；邮件行不重复重要度 | human |
| U1 | Ready | Level 3/2/1 分区、Act 全量可滚动，Quiet 折叠 | unit + human |
| U2 | hover row | 相邻二级显示完整摘要且可进入，不闪旧项 | human |
| U3 | 完成条目 | Gmail thread 移除 `INBOX` 后进入已完成；撤销重新添加 `INBOX` | unit + integration + human |
| U4 | 转 Goal 两次 | 只创建一个 Today Goal，note 无正文，可跳 Goals | unit + human |
| U5 | 置顶/取消置顶 | Gmail thread 添加/移除 `STARRED`；不归档、不改 Level，同 Level starred 优先 | unit + integration + human |
| U6 | Gmail modify 失败 | 条目与计数保持原状态，显示可重试错误，不出现本地假成功 | unit + human |
| U7 | 忽略本次简报 | 只进入当天已忽略，Gmail labels 不变，可恢复 | unit + human |
| U8 | 删除/撤销删除 | Gmail thread trash 后进入已删除；untrash 后回 Inbox；从不调用永久 delete | unit + integration + human |
| S1 | n 个未移除 Act | 菜单栏显示真实 n；0 时只显示 glyph | unit + human |
| C1 | cache 损坏 | 诊断备份后安全空状态，不崩溃 | unit |
| C2 | 新 generation 失败 | 保留上次成功简报与时间 | unit + human |
| L1 | 四语言 | Kaji chrome 完整；邮件内容保持生成语言 | unit + human |
| V1 | build | `swift test`、Release build、codesign 通过 | automated |
| V2 | dev install | 安装本次 candidate，只有一个 Kaji 实例 | install |

## Test map

- `MailBriefSchedulePolicyTests`：D1–D4。
- `MailBriefModelsTests` / schema fixtures：E2–E4、C1–C2。
- `MailBriefCandidatePolicyTests`：G1–G3。
- `MailBriefExecutorTests`：E1、E4，使用假 process runner。
- `MailBriefOAuthTests` / fake Keychain：O1–O3。
- `MailBriefPresentationTests`：Level 分区与排序、P1、U1、U3–U8、S1。
- `GmailMailBriefClientTests`：Inbox query、thread label modify、trash/untrash、幂等与失败不提交，G1–G3、U3、U5–U8。
- `ModulePrefsLogicTests` / `MenuBarSlotLogicTests`：M1–M2、S1。
- `LocalizationTests`：L1。
- Human smoke：M2、O1/O3/O4、P1/P2、U1–U8、S1、C2。

任何单测不得访问真实 Gmail、Google OAuth 或 Codex cloud。真实 Codex 只在明确的 integration smoke 中用测试 fixture，不使用真实邮件。

## Done

- 所有 Acceptance 都有对应自动或人工验证证据。
- `swift test`、Release build 与 codesign 通过。
- 使用测试 Gmail 账号完成 OAuth → 手动生成 → hover → 打开 Gmail → Flag/unflag → Archive/unarchive → Delete/undo → 忽略/恢复 → 转 Today Goal smoke。
- module 关闭后用进程/网络观察确认没有 timer、Gmail request 或 Codex child。
- candidate 重装到 `/Applications/Kaji.app` 后只运行一个实例；用户 smoke 确认前不 commit/push/release。

## Rollback

- 关闭 Mail Brief 即停止全部活动；Disconnect 删除 credential。
- 删除 `mail-brief-cache-v1.json` 与 Keychain item 可清空状态。
- module ID 默认 Off，回滚二进制不改变现有 Goals、AI News 与 MCP 数据。
- 若 Google verification 或 Codex CLI 稳定性阻塞，保持 module 未发布，不降级为更宽权限或保存正文。

## Likely file touch list

- `Sources/KajiCore/ModulePrefsLogic.swift`
- `Sources/KajiCore/GoalHorizonModel.swift` / menu-bar slot logic
- `Sources/KajiCore/MailBriefModels.swift`（新增）
- `Sources/KajiCore/MailBriefSchedulePolicy.swift`（新增）
- `Sources/KajiCore/MailBriefCandidatePolicy.swift`（新增）
- `Sources/Kaji/Prefs.swift`
- `Sources/Kaji/MailBriefOAuthClient.swift`（新增）
- `Sources/Kaji/MailBriefGmailClient.swift`（新增）
- `Sources/Kaji/MailBriefExecutor.swift`（新增）
- `Sources/Kaji/MailBriefStore.swift`（新增）
- `Sources/Kaji/AppDelegate.swift`
- `Sources/Kaji/StatusItemView.swift`
- `Sources/Kaji/KajiPopoverView.swift`
- `Sources/Kaji/SettingsView.swift`
- `Sources/KajiCore/LanguageLocalization.swift`
- `Tests/KajiTests/`

## 批准前必读

- **邮件正文会离开本机进入 Codex 云端。** Connect Gmail 前必须明示；token 永远不进模型。
- **Google `gmail.modify` 扩大了授权能力。** 自用 test user 可开发，公开发布可能被 OAuth verification 卡住；UI 与 client 必须把写操作限制在用户显式触发的 Archive / Flag / Move to Trash。
- **完整覆盖不等于一次塞入无限上下文。** 每个 Codex batch 最多 100 threads，按 checkpoint 分批直至 Inbox snapshot 全部完成；中途必须显示 X / Y，不能假装完整。
- **三块只属于 Level 区头，不属于邮件行。** 深浅灰表达整个区域的重要度；按 Goals Today / Week 的分区语言实现，避免逐行视觉噪音。
