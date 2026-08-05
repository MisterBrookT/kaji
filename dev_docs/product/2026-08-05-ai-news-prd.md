# PRD：AI News Module

> 日期：2026-08-05  
> 状态：Draft，待产品确认  
> 类型：Product Requirements Document  
> 数据提供方：AI HOT

## 一句话

**AI News 把今天 AI 圈正在关注的内容，低摩擦地带到菜单栏。**

## 背景

Kaji 不只是一个默认安静的 menu-bar tool。它更接近个人用户：把每天真正需要知道的信号放在离用户最近的位置，并降低获取它们的摩擦。

Quota 回答“我还能用多少”，Goals 回答“我今天要做什么”，System 回答“电脑现在怎么样”，Work 回答“当前节奏是什么”。AI News 回答：

> **今天 AI 圈正在关注和尝试什么？**

AI News 是第五个独立 module，不并入 Quota。Kaji 不重新判断热点、不做个性化推荐，也不建立自己的资讯排序；AI HOT 返回什么，Kaji 就忠实展示什么。

## Product decision

- AI News 与 Quota、Work、System、Goals 同级。
- 沿用当前 popover page 架构，不借此重构整个 Kaji shell。
- module 默认关闭，由用户在 Settings 主动开启。
- 开启后在菜单栏拥有常驻、可点击的独立入口；不显示未读数字，不发通知。
- 点击菜单栏入口直达 AI News page。
- 主页面可滚动浏览 AI HOT 当前 Top 10。
- hover 一条新闻，在相邻二级 popover 中显示摘要。
- 点击新闻使用默认浏览器打开上游链接。

## 用户价值

用户不需要打开资讯网站、社交媒体或主动组织搜索，就能快速知道今天 AI 圈最热的主题。Kaji 不试图成为完整阅读器；它缩短的是“想知道今天大家在玩什么”到“看到答案”的路径。

成功体验应当是：

1. 用户点击菜单栏中的 AI News 入口。
2. 一眼看到按 AI HOT 热度排列的主题。
3. hover 感兴趣的条目即可理解摘要。
4. 真正想深入时，点击打开上游页面。

## Information architecture

### 菜单栏

AI News 开启时显示一个安静的独立 glyph，与其它可选 module slot 一致。

- 它是入口，不承担未读压力。
- 不显示红点、badge 或滚动标题。
- 点击直达 AI News page。
- module 关闭时 glyph 消失，后台刷新停止。

具体 glyph 在 Feature Spec 中按现有 Mono 语言确定，本 PRD 不锁定图形。

### 一级 popover

一级页面显示可滚动的热点列表。每行包含：

- 热度位置：使用 AI HOT 返回的 `rank`。
- 标题：使用上游标题，不由 Kaji 改写。
- 来源：主要来源；可用时显示独立信源数量。
- 时间：使用上游 `latestAt`，按用户当前语言显示相对时间。

“热度”不得伪造成不存在的百分比。AI HOT v1 hot-topics 不公开内部 heat score；Kaji 使用 rank 和 `sourceCount` 表达上游热度。

页面底部提供低权重、可发现的 `Data source: AI HOT` 链接，满足公开产品 attribution。

### Hover 二级 popover

hover 条目后，在一级右侧相邻展示二级 popover：

- AI HOT story digest。
- 最新动态。
- 来源数量与最新时间。
- 打开链接。

交互要求：

- hover 后短延迟出现，避免扫过列表时抖动。
- 一级与二级之间没有不可达空隙。
- 鼠标进入二级后保持打开。
- 同时只展示一个条目的详情。
- 条目没有公开 story / digest 时，显示已有元数据，不编造摘要。
- 错误不影响一级列表继续使用。

单击一级条目直接使用默认浏览器打开 API 返回的上游链接；hover 负责预览，不增加第三层导航。

## 内容与排序合同

首版以 AI HOT v1 为唯一 provider：

- 热点列表：`GET /api/v1/hot-topics`
- hover 摘要：当热点包含 `links.story` 时，提取其 `publicId` 并请求 `GET /api/v1/stories/{publicId}`

规则：

- 保持 hot-topics 返回顺序，不在本地重排。
- Top 10 是 AI HOT 定义的当前多信源热点。
- Kaji 不混入 `/items` 的“最新精选”来改变热点列表。
- `sourceCount` 表示独立信源数量，不叫浏览量或用户热度。
- `links.story` 缺失时不得自行构造 story ID。
- story 发生 `308` 合并时跟随官方 surviving ID。
- 所有字段按可空或未来扩展处理，不因新增 category / source 值崩溃。

官方合同：

- [AI HOT v1 OpenAPI](https://aihot.virxact.com/openapi-v1.json)
- [AI HOT API Terms](https://aihot.virxact.com/terms)
- [AI HOT Agent / API 接入](https://aihot.virxact.com/agent)

AI HOT Skill 仅帮助开发者理解 API，不进入 Kaji bundle，也不是用户依赖。

## Refresh

用户可在 Settings → AI News 选择刷新间隔：

- 1 小时
- 3 小时
- **5 小时（默认）**
- 12 小时
- 24 小时

行为：

- 首次开启 module 时立即加载。
- 有缓存时先显示缓存，不阻塞 UI。
- 距上次成功刷新超过配置间隔时发起条件请求。
- 定时刷新不依赖 popover 当前是否打开，但只在 module 开启时运行。
- 所有请求保存并发送 `ETag` / `If-None-Match`；`304` 只更新时间，不重复解析或写入。
- 尊重服务器 `Cache-Control`；不得比当前 hot-topics 的 300 秒共享缓存更频繁。
- `429` / `503` 尊重 `Retry-After`，不并发重试。
- 网络失败时保留上次成功缓存，不清空页面。
- 手动刷新允许存在，但同样尊重最短缓存与退避边界。

官方 v1 表明 hot-topics 持续重算、共享缓存当前为 300 秒；默认 5 小时是 Kaji 的低打扰产品选择，不是 AI HOT 的内容更新频率。

## Read state

- 用户打开过的条目在本机轻微变淡。
- 已读状态不改变排序，不隐藏条目。
- 不显示全局未读数或通知。
- 不上传阅读历史。
- 当热点退出 Top 10 后，本地记录可按有限窗口自然清理；具体保留期由 Feature Spec 确定。

## Settings

AI News 设置只包含：

- module 开关。
- 刷新间隔。

不提供：

- 自定义来源。
- 分类筛选。
- 个性化关键词。
- 排序算法。
- 通知频率。
- 摘要模型选择。

Kaji 跟随 AI HOT 的最新稳定 v1 合同，不 vendoring 或固定 Skill 版本。API 合同升级必须继续兼容当前缓存，不能静默切到旧接口。

## States

### Loading

首次没有缓存时显示短 loading state，页面结构不跳动。

### Ready

显示 AI HOT Top 10、最后成功更新时间和 attribution。

### Empty

API 成功但没有热点时明确显示“暂无热点”，不把它当成错误。

### Stale

刷新失败但存在缓存时继续显示缓存，并以低权重标示上次更新时间；不弹通知。

### Error

首次加载失败且无缓存时显示简短错误与重试入口。保留可用于诊断的 request ID，但不向普通界面倾倒 API 日志。

### Disabled

不出现在 popover page、菜单栏和后台任务中。

## Privacy and safety

- 仅访问 AI HOT 官方匿名只读 HTTPS v1 API。
- 不需要 API key、cookie 或 AI HOT 账号。
- 不上传 Kaji 配置、设备信息、Goals、quota 或阅读历史。
- API 返回的标题、摘要和链接均视作不可信数据，只作为文本展示。
- 不执行返回内容，不下载附件，不加载第三方网页脚本。
- 外部链接交给系统默认浏览器。
- 本地缓存只保存展示所需响应、ETag、更新时间和已读 ID。

## Non-goals

- 不做无限信息流。
- 不做新闻搜索、分类页或完整历史。
- 不做个性化推荐。
- 不做收藏、稍后读、隐藏或“不感兴趣”。
- 不做通知、红点与未读焦虑。
- 不抓取第三方原文。
- 不训练或调用 Kaji 自有模型重写摘要。
- 不支持多 news provider。
- 不重构现有五个 module 的整体导航。

## Success criteria

第一版成功不以停留时长衡量。它应满足：

- 开启后，用户一次点击菜单栏入口即可看到当前 AI HOT Top 10。
- 列表严格保持上游热度顺序。
- 每条一眼可见标题、rank、来源、时间；hover 可用时显示真实 digest。
- 缓存存在时打开无等待。
- 默认最多每 5 小时进行一次正常刷新，条件请求避免重复下载。
- 关闭 module 后菜单栏入口、页面和刷新任务全部消失。
- 离线或 AI HOT 故障不会清掉上次成功内容。
- 不采集用户隐私，不制造通知压力。

## Open implementation questions

以下问题留给 Feature Spec 与代码调研，不改变 PRD：

- 菜单栏 glyph 的具体图形与点击命中区域。
- 二级 popover 的精确尺寸、hover delay 与退出宽限。
- 缓存文件位置、schema version 与已读 ID 保留期。
- Swift URLSession adapter、ETag store 与 module timer 的具体所有权。
- API 响应 fixture、decode tolerance 与 UI smoke cases。

## 下一步

1. 用户确认本 PRD。
2. 基于当前 Kaji module architecture 写可验收的 Feature Spec。
3. tests → API adapter/cache → module lifecycle → UI → Settings → Release build。
4. 重装 `/Applications/Kaji.app` 做人工 smoke。

