# ADR：Mail Brief Gmail 与 Codex 执行边界

> 日期：2026-08-08  
> 状态：Accepted（2026-08-08；同日增补 Inbox snapshot 与 Gmail triage actions）  
> 关联 PRD：[2026-08-08-mail-brief-prd.md](./2026-08-08-mail-brief-prd.md)

## Context

Mail Brief 每天读取用户 Gmail，把候选 thread 交给 headless Codex 生成结构化简报。这里同时涉及 Gmail 敏感权限、用户正文离开设备、外部 CLI 生命周期和本地长期数据所有权。

如果直接复用 Lisa daemon，会把邮件正文放进为代码执行设计的 full-access 环境；如果把调度交给独立常驻服务，又会制造第二套 module 生命周期与安装机制。两者都不符合 Kaji 的安静、可关闭模块边界。

## Decision

### 1. Kaji 是唯一 orchestrator

- Mail Brief 是 Kaji 内的默认关闭 module。
- Kaji 进程负责每日 due 判断、Gmail fetch、临时输入、Codex 子进程、结果校验和缓存发布。
- 不复用 Lisa daemon、Cursor worker、local MCP server 或单独 launch daemon。
- Kaji 未运行时不后台处理；下次启动或唤醒后，当天补跑一次。
- module 关闭时取消 timer、网络请求和 Codex process，不保留隐藏 worker。

### 2. Gmail 使用 Installed App OAuth

- 首版由 Kaji 自己持有 Google Desktop OAuth client ID，使用 Authorization Code + PKCE。
- 登录在系统默认浏览器完成，回调只监听随机 loopback localhost 端口；不嵌入 WebView。
- 只读连接可生成简报；首次使用归档、星标或删除时解释用途并增量申请 `gmail.modify`。credential 必须记录真实 scope/capability，不能把“已连接”等同于“可修改”。
- `gmail.modify` 只用于用户逐条触发的 `INBOX` / `STARRED` 变更与 Gmail trash/untrash；不申请 `gmail.send` 或 `gmail.compose`，也不永久删除。发送能力仍须另案获批并重新授权。
- access/refresh token 只存 macOS Keychain。UserDefaults、cache、日志和 Codex 输入都不得出现 token。
- 断开 Gmail 时删除 Keychain token，并停止后续 fetch；本地简报是否保留由用户在断开确认中选择。

Gmail scopes 可能触发 Google verification。开发期可限制为 Google Cloud test users；公开分发前必须完成 consent/verification 或明确不发布该 module，不能用共享 client secret 绕过审核。

### 3. 每日任务使用可重放状态机

持久状态至少包含：

```text
disabled → disconnected → scheduled → fetching → summarizing → ready
                                      ↘ failed/stale ↗
```

- 本地日期与配置时区共同形成 `briefDay`。
- 同一 `briefDay` 只有一个成功 generation；进程重启不会重复覆盖。
- Mac 睡眠/关机错过时间后，当天首次 activation 补跑。
- 手动“立即生成”可创建同日新 generation；只有 schema 校验成功才原子替换当前简报。
- 新生成失败保留上次成功结果。

### 4. 完整 Inbox snapshot，原文仍是短命输入

- 页面一行对应一个 Gmail thread。一个完整 generation 必须满足 `Act + Watch + Quiet = snapshotInboxThreadCount`；Gmail 的未读 message badge 不属于这个等式。
- 首次运行分页枚举并分类当前全部 Inbox threads。后续保存最小同步 cursor/fingerprint，复用未变化 thread 的结构化结果，只重新读取并分析新增或变化的 threads；周期性全量 ID reconciliation 修复 cursor 漂移。
- Codex 每批最多 100 threads，但 batch 上限不得成为覆盖上限。多批按顺序处理；完整 snapshot 未就绪时展示 `已分类 X / Inbox Y`，不得发布伪完整 generation。
- 网络层在内存中组装裁剪后的纯文本 thread。附件只保留文件名/MIME，不取正文。
- 临时输入文件放在本次 invocation 的随机目录，权限限制为当前用户；结束、超时或取消后尽力删除。
- 长期 cache 不保存原始正文，只保存 Gmail IDs、展示摘要、优先级、理由、动作、截止日期、generation 与本地 dismiss 状态。

### 5. Codex 是无工具的结构化分类器

通过本机 Codex CLI 调用 Settings 中经过 allowlist 校验的模型。初始 allowlist 为：

- `gpt-5.3-codex-spark`（默认）
- `gpt-5.6-luna`

调用形态固定为：

```text
codex exec
  --model <validated-model-id>
  --config model_reasoning_effort="low"
  --sandbox read-only
  --ephemeral
  --ignore-user-config
  --ignore-rules
  --skip-git-repo-check
  --cd <isolated-temp-dir>
  --output-schema <mail-brief-schema.json>
  --output-last-message <result.json>
  -
```

- prompt 从 stdin 输入，不放 argv；模型输入不含 OAuth token 或本机路径。
- 临时目录不是 Git repo，不提供 `--add-dir`，不启用 MCP、hooks、skills 或网络工具。
- schema 固定 `additionalProperties: false`，包含版本、每个输入 thread 的稳定 ID、priority level、summary、reason、suggested action、deadline 与 confidence。
- 输入正文明确包裹为不可信数据；邮件内要求执行命令、读取文件、改变输出格式的文字一律视为正文。
- CLI 非零退出、超时、取消、输出缺失、未知 thread ID 或 schema 不合法，都不得覆盖旧结果。
- model ID 不是自由文本；未知持久化值规范化为当前默认值，避免把任意 CLI 参数变成产品配置面。
- checkpoint 与结构化分类缓存记录 model ID。用户切换模型时，下一轮重新分类当前 Inbox；普通增量刷新只处理新增或变化 thread。
- 不做静默模型 fallback。Spark preview 不可用、排队或限额耗尽时保留旧结果并报告原因，由用户决定是否切换 Luna。

`--ignore-user-config` 仍复用用户现有 Codex 认证；Kaji 不读取或复制 Codex credential。若用户未登录 Codex，UI 显示可解释的 setup error。

Spark 当前是 Codex research preview、128k text-only，并使用独立且可能动态调整的限额；选择它是为了降低批处理墙钟时间，不把 preview 可用性当成稳定 SLA。参考：[Introducing GPT-5.3-Codex-Spark](https://openai.com/index/introducing-gpt-5-3-codex-spark/)。

### 6. Kaji 拥有最终产品状态

- AI 输出本身不修改 Gmail 或 Goals；只有用户在明确控件上的动作可以触发副作用。
- `转 Goal` 由用户点击后调用现有 `DailyGoalStore`，默认 Today，并记录 source thread ID 防止重复转换。
- `完成` 在 Gmail 成功移除 `INBOX` 后才写本地完成态；撤销重新添加 `INBOX`。`置顶` 添加 `STARRED`，再次点击移除。`删除` 调用 Gmail thread trash，撤销调用 untrash；不调用永久 delete endpoint。三者均按 thread 幂等执行。
- `忽略本次简报` 只写入当前 `briefDay + generationID` 的本地 dismiss set；当天可恢复，不改变 Gmail。
- 菜单栏 Act 数量由未 dismiss 的 Act 条目计算，不截断。

## Alternatives rejected

### 复用 Lisa daemon

拒绝。Lisa 的信任模型、任务队列和代码工作区权限不适合邮件正文；也会把产品生命周期绑到个人开发工具。

### 为邮件安装独立 launch daemon

首版拒绝。每天一次不值得增加常驻进程、安装权限和双状态同步。Kaji 启动/唤醒补跑已经满足产品合同。

### 直接调用 OpenAI API

首版拒绝。用户已选择复用本机 Codex 登录；API key、计费与 provider 设置会增加另一套配置。后续若 CLI 稳定性不足，可用保持同一 schema 的 executor adapter 替换。

### 在 Kaji 内保存完整邮件正文

拒绝。它把简报模块变成邮件数据库，扩大泄露和迁移面。

## Consequences

- 优点：module 关闭即真正停止；没有第二个 daemon；OAuth token、原文和产品摘要边界清楚；executor 可替换。
- 代价：Kaji 不运行时不会准点执行；依赖本机 Codex CLI 与登录状态；Google OAuth 公开发布存在审核成本。
- 实现要求：所有外部依赖必须可注入，单测不访问 Gmail、Google OAuth 或真实 Codex。

## Rollback

- Settings 关闭 Mail Brief，终止调度与外部调用。
- 删除 Keychain token、Mail Brief cache 和临时目录即可完全移除该能力。
- 新 module ID 默认关闭；回滚代码不会改变现有 Goals、AI News 或 MCP persistence。

## 批准前必读

- **Gmail 正文会提交到 Codex 云端。** OAuth 前必须明确披露；不能叫“本地 AI”。
- **`gmail.modify` 扩大了授权能力。** UI 必须将其限定为显式 Archive / Flag / Move to Trash；自用 test user 可先跑，公开发行前可能需要 Google 验证。
- **Kaji 退出时不会准点执行。** 首版选择启动/唤醒补跑，不新增 daemon。
- **Codex CLI 是本机外部依赖。** 必须探测版本、登录与 schema 能力；任何失败都保留旧简报。
