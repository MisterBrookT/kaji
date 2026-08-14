# PRD：Mail Brief Module

> 日期：2026-08-08  
> 状态：Approved（2026-08-08）  
> 类型：Direction / Product Requirements Document  
> Primary：new feature  
> Secondary：Gmail integration、AI prioritization、privacy、module lifecycle

## 一句话

**Mail Brief 每天一次把 Gmail 中真正需要注意的邮件压缩成一份安静、可解释、可行动的个人简报。**

## 背景

邮件的重要问题不是“看不到”，而是噪音与行动混在一起。用户需要知道：今天哪些邮件要求自己回复、确认或安排，哪些只是值得留意，哪些可以安静略过。

Kaji 不替代 Gmail，也不成为完整邮件客户端。Mail Brief 只缩短这条路径：

```text
打开多个邮箱页面 → 阅读线程 → 判断优先级 → 记住下一步
```

变成：

```text
打开 Kaji → 看见今天真正需要处理的事项 → 回 Gmail 或转成 Goal
```

## Product position

Mail Brief 是默认关闭的第一方 module，与 Quota、Work、System、Goals、AI News 同级。

它不是 Inbox，不追求实时，不显示所有邮件，不制造未读压力。Kaji 只回答：

> **今天的邮件里，什么值得占用我的注意力？**

## 目标用户与 Job

首版服务单个 Gmail 账号的个人用户。用户每天只想处理一次邮件，希望在进入 Gmail 前得到一份可信的判断：

- 哪些邮件需要自己行动。
- 为什么它们重要。
- 是否存在截止时间、等待回复或风险。
- 下一步更适合回复、转成 Goal、继续观察还是忽略。

## 核心体验

每天在用户选择的本地时间运行一次。成功后，Mail Brief 页面保留当天结果，直到下一次成功处理。

一级页面不人为截断 Act；当天需要执行的事项都可滚动查看。它按行动价值分区，而非在每一行重复显示重要度。页面只承担快速扫视：每个 Level 区域有独立标题，区内邮件行显示原始标题与轻量操作，不直接铺开摘要。

### Act

存在明确提问、确认、付款、审批、材料、会议或截止时间，需要用户采取行动。

### Watch

重要但暂时不要求行动，例如项目状态、行程变化、关键通知。

### Quiet

推广、newsletter、自动回执和低价值通知。默认不在一级页面逐条展示，只在底部显示“已安静处理 n 条”。

每条 thread 的 AI 结果包含：

- 原始主题与发件人。
- 1–2 句中文摘要。
- `urgent / important / normal` 优先级。
- 一句可解释理由。
- 建议动作：`reply / createGoal / watch / none`。
- 可识别时显示截止日期。

## Actions

- 使用默认浏览器打开 Gmail 原 thread。
- `完成`：明确归档对应 Gmail thread，只移除 `INBOX` label，不删除或标记已读；当天可撤销归档。
- `置顶`：对应 Gmail `STARRED`（其他客户端常称 Flag），可再次点击取消；不改变 AI Level。
- `删除`：将对应 Gmail thread 移入 Trash；当天可撤销。它不是永久删除。
- 使用条目上的显式按钮，把建议事项转成 Kaji Goal；默认进入 Today。
- `忽略本次简报`：只隐藏 Kaji 当天条目，不修改 Gmail，当天可恢复。

打开、hover、转 Goal 或生成摘要均不得自动归档或删除。Gmail 写动作必须在服务端成功后才提交本地状态；失败时保留原条目并允许重试。Mail Brief 仍不发送、永久清空 Trash、标记已读、snooze 或自动回复邮件。

## Gmail contract

- Gmail first，首版单账号。
- 使用 Google OAuth；展示只需 read capability，归档、星标与 Move to Trash 按需申请 `gmail.modify`，不申请发送权限。
- OAuth token 存入 macOS Keychain，不写 prefs、日志或模型输入。
- 每次简报对应一个完整的当前 Inbox thread snapshot。Act + Watch + Quiet 的 thread 数之和必须等于该 snapshot 的 Inbox thread 总数。
- 首次连接分页同步全部 Inbox threads；后续复用未变化 thread 的结构化分类，只读取并重新分析新增或变化的 threads，另做轻量全量 ID reconciliation 防止漂移。
- `100` 仅是单次 Codex batch 上限，不是每日或 Inbox 覆盖上限。多 batch 未完成时显示“已分类 X / Inbox Y”，不得用 Quiet day 或完整简报文案掩盖未处理项。
- module 关闭后停止 Gmail fetch、每日任务与 AI 调用；本地缓存按保留策略清理。

## Daily schedule

- 正常情况每天只自动运行一次。
- 用户可选择本地运行时间；Draft 默认建议 `09:00`。
- 错过时间（Mac 睡眠或关机）后，当天首次可运行时补跑一次，不重复执行。
- 同一天重复启动 Kaji 不重复生成简报。
- Settings 提供低权重 `立即生成`，用于首次连接、失败重试与调试；它不是常规刷新入口。
- 新一次失败时保留上次成功结果，并明确标记最后成功时间。

## AI execution

首版使用 headless Codex，并在 Settings 提供受控模型选择：

```text
default model = gpt-5.3-codex-spark
alternative = gpt-5.6-luna
reasoning effort = low
```

选择原因：每日批量邮件分类属于高吞吐、结构化判断。Spark 优先验证低延迟批处理体验；Luna 保留为用户明确选择的稳定替代。模型不可自由输入，reasoning effort 固定为 low。

官方参考：[GPT‑5.3‑Codex‑Spark](https://openai.com/index/introducing-gpt-5-3-codex-spark/)、[GPT‑5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)

产品合同：

- 一次运行批量处理候选 threads，不为每封邮件单独启动一个 agent。
- executor 只接收裁剪后的 thread 内容与必要元数据，不接收 Gmail OAuth token。
- 输出必须符合版本化 JSON schema；解析失败不覆盖旧结果。
- prompt injection 邮件正文只作为不可信数据，不得改变 system 指令或触发工具。
- headless process 使用独立临时工作目录；不获得 Kaji repo、Home 目录或任意 shell 写权限。
- 临时输入在处理结束后删除；日志不得包含正文、地址、token 或附件内容。
- 模型切换只允许受控列表；切换后下一轮重新分类当前 Inbox，普通运行继续按增量缓存处理。Spark 不可用时不得静默换模型。
- 首版不实现 Cursor/local adapter 或任意 model/provider 输入。

headless executor 的具体 sandbox、Codex CLI 参数、认证与失败恢复由配套 Technical Design / ADR 定义，本 PRD 不把 Lisa daemon 直接复用成邮件执行器。

## Priority contract

AI 必须同时返回判断与理由，不只返回不可解释分数。

优先信号包括：

- 直接向用户提问或点名请求。
- 明确截止日期、会议、付款、合同、审批、行程变化。
- 用户正在等待或对方正在等待回复。
- Gmail Important 与星标等用户已有信号。
- 发件人关系与 thread 上下文。

降权信号包括：

- newsletter、推广、自动回执、批量通知。
- 没有行动要求的系统状态消息。
- 无法确认的营销式紧迫措辞。

模型低信心时进入 Watch，不得擅自判为 Quiet。用户后续纠正机制留给第二阶段，不在首版建立学习系统。

## Surface

### 菜单栏

开启后提供一个安静的独立入口。菜单栏显示当天仍在 Inbox、未被 Kaji-only ignore 的真实 Act 数量，不设产品上限；没有 Act 时只显示 glyph，不显示 `0`、红点或通知。

### 一级 popover

一级沿用 Goals 的 Today / Week 分区语言。不同 Level 各自形成区域；每个区域标题包含三个非常小的 Mono 灰色方块，用深浅灰表达该区域的重要度。邮件行本身不绘制方块。

每行只显示：

- 原始邮件标题；空间允许时附低权重发件人。
- `完成`、`置顶` 与 `转 Goal`；仅本地忽略放入次级操作。

重要度不使用红黄绿、白色空心或抽象百分比。三个位置始终是有填充的灰色小块：激活位使用较深灰，非激活位使用更浅灰。

```text
3 深 + 0 浅  最高，需要优先行动
2 深 + 1 浅  重要，建议今天处理
1 深 + 2 浅  值得留意，暂不紧急
0 深 + 3 浅  Quiet
```

深灰数量是区域 Level 的离散展示，排序仍由完整 priority contract 决定。三个浅灰块代表 Quiet；Quiet 默认折叠。区内不再重复重要度标记，避免每行视觉噪音。

### Hover 二级 popover

参考 AI News，hover 一级条目后，在相邻二级 popover 展示完整简报信息：

- 发件人与原始标题。
- 1–2 句中文摘要。
- 为什么重要。
- 建议动作与可识别的截止日期。
- 打开 Gmail 原 thread 的入口。

交互要求：

- 短延迟出现，避免扫过列表时抖动。
- 一级与二级之间没有不可达空隙；鼠标进入二级后保持打开。
- 同时只展示一个 thread 的详情。
- 点击标题或二级中的打开入口，使用默认浏览器打开 Gmail。
- 摘要失败时仍保留一级标题，不编造内容。
- 不增加第三层页面，不把完整邮件正文复制进 Kaji。

页面底部只保留：

- 最后成功生成时间。
- Quiet 数量。
- 低权重失败/过期状态。

## States

- **Disconnected**：说明 Gmail 未连接，提供 OAuth 入口。
- **Scheduled**：已连接但今天尚未到运行时间，显示下次时间。
- **Running**：保持上次结果，显示低权重处理中状态。
- **Ready**：展示当天 Act / Watch 简报。
- **Quiet day**：没有 Act / Watch，明确显示“今天没有需要处理的邮件”。
- **Stale**：本次失败但有旧结果，保留内容并显示最后成功时间。
- **Error**：无缓存且 Gmail 或 Codex 失败，给出重试和诊断入口。
- **Disabled**：页面、菜单栏入口、Gmail fetch 与 daily job 全部停止。

## Privacy and safety

- 用户必须明确完成 Gmail OAuth，module 默认关闭。
- Gmail 修改权限只用于显式归档/撤销、星标/取消星标与移入/移出 Trash；Kaji 无法代表用户发信或永久清空 Trash。
- 邮件正文会被发送到用户已登录的 Codex 服务进行分析，连接前必须明确告知。
- OAuth token 永不进入 Codex prompt。
- 原始正文不做长期业务缓存；只保留生成简报所需的最小临时数据。
- 长期本地记录只保留 thread/message ID、摘要、优先级、理由、建议动作、截止日期与处理时间。
- 附件首版只读取文件名与 MIME 元数据，不上传或解析附件正文。
- 邮件正文视为 prompt injection 不可信输入；模型没有邮件写权限、Gmail token 或任意系统执行权限。

## Non-goals

- 不做邮件正文阅读器、搜索、文件夹或通用标签管理；完整 Inbox snapshot 只服务于每日分类覆盖与 triage actions。
- 不实时监听，不发系统通知，不按新邮件逐封调用 AI。
- 不自动发送、回复、删除、归档、snooze 或取消订阅；Archive、Flag、Delete 只能由用户逐条明确触发。
- 不生成可直接发送的回复草稿。
- 不支持 Outlook、IMAP 或多 Gmail 账号。
- 不解析附件正文。
- 不建立长期联系人画像或自动学习优先级模型。
- 不把 Lisa task queue、GitHub Issue 流程或 Lisa daemon 当作邮件数据层。
- 不在首版实现 Cursor、local model、任意 provider 或自由 model ID。

## Success criteria

第一版成功不是让用户在 Kaji 里停留更久，而是每天更快决定是否需要进入 Gmail：

- 每天最多自动运行一次，睡眠补跑不产生重复简报。
- Act 不设展示数量上限；Quiet 默认不占据主列表。
- 完整同步后 Act + Watch + Quiet 必须等于当前 Inbox thread 总数；同步中必须显示 X / Y，不允许静默遗漏。
- 每个可见 thread 都有摘要、优先级、理由与建议动作。
- 一级按 Level 分区；小方块只出现在区头，邮件行仅展示标题和操作；hover 二级可读完整摘要。
- 用户可在一次点击后打开原 Gmail thread。
- 转 Goal 必须由用户点击按钮触发，默认创建到 Today，并保留来源 thread ID。
- 完成条目归档 Gmail，置顶映射 Gmail `STARRED`，删除将 thread 移入 Trash；忽略才是只修改 Kaji 当天简报。
- Gmail token 不进入模型输入或日志。
- 单个 thread 解析失败不导致整个简报丢失。
- module 关闭后无 Gmail fetch、Codex process 或定时任务。
- 失败时保留旧结果，不制造通知压力。

## Product decisions

- 默认本地运行时间为 `09:00`，用户可在 Settings 修改。
- 菜单栏显示尚未处理的真实 Act 数量，不截成 `3+`。
- 一级 popover 像 Goals 的 Today / Week 一样按 Level 分区；hover 二级 popover 展示完整摘要。
- 每个 Level 区头使用三个 Mono 灰色实心小方块表达重要度；邮件行不重复绘制。深灰位越多越重要，Quiet 是三个浅灰块，不使用白色空心。
- 转 Goal 是用户显式选择，首版默认进入 Today。
- 完成/撤销完成映射 Gmail `INBOX` label，置顶映射 `STARRED`，删除/撤销删除映射 Gmail Trash；忽略本次简报保持为 Kaji-only。
- `立即生成` 始终作为低权重操作保留，不成为高频刷新入口。

## Review risks

- **邮件正文会离开本机。** headless Codex 仍是云端处理；OAuth 前必须清楚披露，不能称为 local-only。
- **优先级可能静默错判。** 低信心进入 Watch、Quiet 不自动改 Gmail，是首版安全阀。
- **方块容易被误解为完成度。** 二级详情必须用文字说明重要原因；Feature Spec 的人工 smoke 要验证用户能把它理解为重要度，而非 Todo 进度。
- **Codex CLI 不是邮件服务 API。** 认证、sandbox、输出契约和版本兼容必须单独写 ADR/Technical Design，不能照搬 Lisa 的 full-access executor。
- **Kaji 容易变成第二个 Inbox。** 完整覆盖不等于完整展开：Quiet 默认折叠、正文只在 hover 摘要中出现、每天一次且 module 默认关闭；不得增加搜索、文件夹导航或阅读器表面。

## 下一步

1. 用户确认本 PRD 的整体方向。
2. PRD 标记 approved。
3. 写 executor/privacy ADR 与 Technical Design。
4. 写可验收 Feature Spec，覆盖 Gmail、daily scheduler、AI schema、module lifecycle 与 UI。
5. tests → code → human smoke；确认前不 commit / push / release。
