# Feature Spec：AI News Module

Status: approved for Lisa execution  
PRD: [2026-08-05-ai-news-prd.md](../product/2026-08-05-ai-news-prd.md)

## 类型

Primary: new feature  
Secondary: external API integration、module lifecycle、local cache、menu-bar interaction

## 目标

为 Kaji 增加默认关闭的第五个 `AI News` module。开启后，用户可从菜单栏常驻入口直接进入 AI HOT 当前 Top 10，滚动浏览标题、热度位置、来源与时间，hover 查看 AI HOT story digest，点击打开上游页面。

Kaji 不自行抓新闻、不重新排序、不生成摘要。AI HOT Skill 仅供实现者理解接入；运行时直接访问 AI HOT 官方匿名只读 v1 API。

## In

- `KajiModuleID.aiNews`，稳定页序放在 Goals 之后。
- Settings → Modules 中的 AI News 开关，默认关闭。
- Settings → AI 中的刷新间隔：1h / 3h / 5h / 12h / 24h，默认 5h。
- module 开启时显示独立 menu-bar glyph，点击直达 AI News page。
- 可滚动显示 AI HOT Top 10。
- 每行显示 rank、标题、主要来源、`sourceCount`、`latestAt`。
- hover 相邻二级 popover，按需加载 story digest。
- ETag / 304、本地缓存、stale/error/empty/loading 状态。
- 本地已读状态；已读只变淡，不隐藏、不计 badge。
- Mono Light / Dark、四语言基础文案。
- module 关闭即停刷新、取消未完成请求、隐藏页面与菜单栏入口。

## Non-goals

- 不做无限信息流、搜索、分类、历史页或日报。
- 不做个性化、Kaji 自有排序或摘要。
- 不做通知、红点、未读数字。
- 不做收藏、稍后读、隐藏或“不感兴趣”。
- 不抓取第三方网页或附件。
- 不让用户安装、配置或运行 AI HOT Skill。
- 不支持多 provider。
- 不重构现有 popover page shell。

## 官方合同与版本

新接入只使用：

- `GET https://aihot.virxact.com/api/v1/hot-topics`
- `GET https://aihot.virxact.com/api/v1/stories/{publicId}`
- [AI HOT v1 OpenAPI](https://aihot.virxact.com/openapi-v1.json)
- [AI HOT Terms](https://aihot.virxact.com/terms)

禁止新代码调用计划于 2026-12-31 停服的 legacy `/api/public/*`。

请求使用可识别身份，例如：

```text
Kaji/0.6 (+https://github.com/blackblue-labs/kaji)
```

不得伪装浏览器，不需要 API key、cookie 或账号。

## 数据模型

纯模型放入 `KajiCore`，不得依赖 SwiftUI / AppKit：

```swift
struct AIHotTopic: Codable, Identifiable, Equatable, Sendable {
    let rank: Int
    let id: String
    let title: String
    let sourceName: String
    let sourceCount: Int
    let signalCount: Int
    let sourceNames: [String]
    let latestAt: Date
    let aiHotURL: URL
    let originalURL: URL
    let storyPublicID: String?
}

struct AIHotStory: Codable, Equatable, Sendable {
    let publicID: String
    let title: String
    let latest: String
    let digest: String?
    let digestUpdatedAt: Date?
    let sourceCount: Int
    let latestAt: Date
    let aiHotURL: URL
}
```

API DTO 可独立于持久化模型。Decoder 使用 ISO 8601，允许未来新增字段。未知字段忽略；非关键可空字段不得导致整页失败。必需 identity/title/rank/links 不合法的单条可跳过并记录诊断，不能让一条坏数据清空有效缓存。

`links.story` 是 HTML URL。只有存在时才提取最后一个 path segment 作为 `publicId`；不得从 topic ID 猜测。

`sourceCount` 是独立信源数量，`signalCount` 是覆盖信号数量。UI 不得把它们命名为阅读量、点赞或百分比热度。

## Store 与缓存

新增 `@MainActor AIHotNewsStore: ObservableObject`，至少发布：

- `topics`
- `state`：`idle / loading / ready / stale / empty / failed`
- `lastSuccessfulRefresh`
- `lastError`
- `hoveredStoryByID`
- `readTopicIDs`

网络层与 store 分离，URLSession 可注入；测试使用 fixture/stub，不访问生产 API。

缓存写在 Application Support 的 Kaji 私有目录，使用 versioned JSON + atomic replace：

```text
ai-news-cache-v1.json
```

保存：

- schema version
- topics
- hot-topics ETag
- last successful refresh
- story cache + story ETag（有界）
- read topic IDs + last seen timestamp（有界）

启动读取失败时保留坏文件的诊断副本并回到空状态，不崩溃、不覆盖为看似成功的空缓存。

story cache 与 read IDs 最多保留 30 天；实现可用最近访问时间清理。Top 10 刷新不删除仍在有效期的 story，避免 hover 重复请求。

## 刷新策略

`Prefs.aiNewsRefreshHours` 默认 `5`，合法值仅 `[1, 3, 5, 12, 24]`；未知旧值归一化为 5。

开启 module：

1. 立即加载本地缓存。
2. 无缓存时立即请求。
3. 有缓存且距离成功刷新达到间隔时请求。
4. 有缓存未到期时不请求。
5. 安排单个可取消 timer 到下一次 due time，不使用短周期轮询检查。

运行中修改间隔，取消旧 timer 并按 `lastSuccessfulRefresh + newInterval` 重排。

请求必须：

- 带上次 ETag 的 `If-None-Match`。
- `304` 更新成功检查时间但保留 topics。
- `200` 保持返回顺序，原子更新缓存。
- 读取响应 `Cache-Control`；无论手动刷新或 timer，都不得突破服务器当前 300 秒 freshness floor。
- `429` / `503` 尊重 `Retry-After`；只安排一次延后重试，不循环。
- 超时/5xx 最多一次退避重试；仍失败转 stale/failed。
- 同一 endpoint 同时最多一个请求。

关闭 module：

- invalidate timer。
- cancel hot-topics 与 story tasks。
- 不清空缓存与已读状态。
- 后续 prefs / app activation 不得触发请求。

App 退出取消全部任务。

## 一级 AI News page

沿用现有 `KajiPopoverView` header、页码、footer 与可滚动高度。新增：

- 标题：`AI News`
- 副标题：最后成功刷新相对时间；首次加载时显示 loading。
- topic rows：保持 API rank 顺序。
- 底部 attribution：`Data source: AI HOT`，可点击。
- refresh action：页面内低权重按钮；不得把现有全局 quota refresh 错接为 news refresh。

每行：

```text
[01] Title
     Source · N sources · Xm
```

- rank 固定宽度，Top 10 不画不存在的 heat percentage。
- 标题最多两行。
- 已读条目整体降低对比，但保持可读。
- 点击条目先写本地已读，再用 `NSWorkspace` 打开 API 返回的 `links.original`；URL 不合法时按钮禁用。
- 键盘 focus 后 Return 与点击等价。

## Hover 二级 popover

hover row 约 180–250ms 后显示，离开一级与二级联合区域约 220ms 后关闭。实现沿用 Goals 已有 generation/debounce 约定，避免 timer race。

- 与当前 row 右侧相邻锚定，鼠标无需跨空隙。
- 鼠标进入二级后保持。
- 同时仅一个 detail。
- 首次 hover 有 `storyPublicID` 时按需请求 story。
- story cache 未过期时立即显示。
- digest 存在：显示 digest；`latest` 可作为次级更新。
- digest 为 null：显示 `latest`。
- 无 story ID：显示 topic metadata 与打开链接，不请求猜测 URL。
- story 请求失败：detail 内显示简短错误，一级列表不变化。
- `308` 只跟随同 host、`/api/v1/stories/` 下的 Location；最多一次。

二级 popover 不继续产生三级页面。

## Menu bar

`StatusItemView` 增加可选 AI News slot：

- module 关闭：slot 为 nil，不占宽度。
- module 开启：显示一个 10–11pt Mono SF Symbol glyph，建议 `newspaper`；不显示 badge/count。
- 有缓存、loading、stale 使用同一个 glyph，不用错误红点。
- 点击触发 `MenuBarDestination.aiNews`。
- popover 已打开在其它 page 时，点击切换到 AI News；已在 AI News 时沿用当前关闭行为。
- `statusItemLength` 仅在开启时增加实际 glyph 宽度。

`MenuBarSlotLogic` / destination tests 覆盖 `.aiNews`。

## Settings

### Modules

增加 `AI News` 行，默认 Off，可即时启停。

### AI

保留现有 provider 设置，并增加独立 `AI News` block：

- Refresh：1h / 3h / 5h / 12h / 24h。
- 默认 5h。
- AI News 关闭时仍可查看/调整间隔，但不触发网络。
- 解释性长文不常驻；必要说明放 `.help`。

四语言至少覆盖：

- AI News
- Data source
- Updated …
- Loading / no hot news / retry
- sources
- refresh interval

上游新闻标题、来源、digest 保持原文，不翻译。

## 状态行为

| 状态 | 一级 page |
| --- | --- |
| 首次 loading | 稳定 skeleton / progress，不显示空白 |
| ready | Top 10 + 更新时间 |
| empty | 明确“暂无热点” |
| stale | 显示缓存 + 最后更新时间 + 低权重失败提示 |
| failed 无缓存 | 简短错误 + Retry |
| disabled | page、slot、timer、request 均不存在 |

失败不得清空成功缓存。重新启用先显示缓存，再按 due policy 决定是否请求。

## 隐私与安全

- 只请求 `https://aihot.virxact.com/api/v1/*`。
- 不上传 Kaji prefs、Goals、quota、设备信息或阅读历史。
- 所有返回文本视为不可信纯文本；不得解析为 Markdown command、HTML 或富文本执行。
- 不在 app 内嵌第三方 WebView。
- 点击外链交给默认浏览器。
- 日志不得打印完整响应、用户路径或阅读历史。
- 公共 UI 保留产品级 `Data source: AI HOT` attribution。

## 验收标准

| ID | Given | Expected | Verify |
| --- | --- | --- | --- |
| M1 | 旧 prefs 无 `aiNews` | 升级后 AI News 默认关闭，现有 module 不变 | unit |
| M2 | 开启 AI News | page 位于 Goals 后，页码包含第五页 | unit + human |
| M3 | 关闭 AI News | page/slot 消失，timer/request 取消 | unit + human |
| S1 | 点击 menu-bar AI News glyph | 直接打开/切换到 AI News page | unit + human |
| S2 | AI News 关闭 | glyph 不存在且 status width 不留空 | unit + human |
| A1 | valid hot-topics fixture | 保持 rank 顺序，解码标题/来源/sourceCount/latestAt/links | unit |
| A2 | topic 有 story link | 只从最后 path segment 得到 publicId | unit |
| A3 | 可空/新增字段 | 不崩溃，不因摘要为空丢整页 | unit |
| R1 | 缓存未到 5h | 打开/激活不发请求 | unit |
| R2 | 缓存到期 | 只发一个带 If-None-Match 的请求 | unit |
| R3 | 304 | 保留 topics，不重复写内容 | unit |
| R4 | 修改 refresh interval | 取消旧 timer，按新 due time 重排 | unit |
| R5 | 429/503 | 尊重 Retry-After，无高频循环 | unit |
| C1 | 启动有缓存 | 首帧显示缓存；网络不阻塞 UI | unit + human |
| C2 | 网络失败有缓存 | 显示 stale，不清空列表 | unit + human |
| C3 | 损坏缓存 | 诊断备份，应用不崩溃 | unit |
| U1 | 一级 ready | 可滚动看到 Top 10，包含 rank/title/source/sourceCount/time | human |
| U2 | hover 有 story | 相邻 detail 显示 digest，鼠标可进入且不失焦 | human |
| U3 | hover 无 story/请求失败 | 一级可用，detail 给安全 fallback | human |
| U4 | 点击 topic | 标记已读并在默认浏览器打开 API URL | human |
| P1 | Settings | module 开关与 1/3/5/12/24h 可读写，默认 5h | unit + human |
| L1 | 四语言 | Kaji chrome 本地化，上游内容不翻译 | unit + human |
| V1 | 构建 | `swift test`、Release build、bundle codesign 通过 | automated |
| V2 | 安装 | `/Applications/Kaji.app` 为本次构建并成功启动 | install |

## Test map

- `AIHotModelsTests`：A1–A3。
- `AIHotRefreshPolicyTests`：R1–R5、P1。
- `AIHotCacheTests`：C1–C3。
- `ModulePrefsLogicTests`：M1–M3。
- `MenuBarSlotLogicTests`：S1–S2。
- `LocalizationTests`：L1 key completeness。
- URLSession protocol fixture tests，不调用线上 API。
- Human smoke：M2–M3、S1–S2、U1–U4、P1、L1。

## 实现路线

1. 更新 module/destination/prefs/localization 纯逻辑与失败测试。
2. 在 `KajiCore` 增加 API DTO、domain model、refresh/cache policy 与 fixture tests。
3. 在 app target 增加可注入 client、versioned cache 与 `AIHotNewsStore`。
4. AppDelegate 接入 enable/disable 生命周期、status slot 与 popover destination。
5. 实现一级 page、refresh states、attribution。
6. 实现 anchored hover detail 与 lazy story cache。
7. Settings 增加 module 与 interval。
8. 全量 tests、Release bundle、codesign；PR closes Issue。
9. Lisa install task 重装并启动。
10. 用户按 companion human-smoke 验收。

## Likely file touch list

- `Sources/KajiCore/ModulePrefsLogic.swift`
- `Sources/KajiCore/AIHotModels.swift`（新增）
- `Sources/KajiCore/AIHotRefreshPolicy.swift`（新增或合并）
- `Sources/KajiCore/LanguageLocalization.swift`
- `Sources/Kaji/Prefs.swift`
- `Sources/Kaji/AIHotAPIClient.swift`（新增）
- `Sources/Kaji/AIHotNewsStore.swift`（新增）
- `Sources/Kaji/AppDelegate.swift`
- `Sources/Kaji/StatusItemView.swift`
- `Sources/Kaji/KajiPopoverView.swift`
- `Sources/Kaji/SettingsView.swift`
- `Tests/KajiTests/`

## 批准前必读（风险）

- **这会新增真实网络源。** 必须只用匿名只读 v1 API，ETag 条件请求，默认 5 小时，不做高频轮询。
- **Hot Top 10 没有公开 heat score。** UI 只能显示 rank、sourceCount、signalCount，不能捏造百分比。
- **Hover digest 不是每条都有。** 没有 story link 或 digest 时必须自然降级。
- **旧 API 已宣布停服。** 新实现不得因 Skill 示例方便而接 `/api/public/*`。
- **第五 slot 会增加菜单栏宽度。** 默认关闭；开启后只加单 glyph，不加 badge/count。
- **上游 latest 不等于无版本约束。** 跟随最新稳定 v1 合同，但必须 fixture 测试、容忍新增字段并保留缓存回滚。

## Done / rollback

Done：

- 所有 automated acceptance 绿。
- PR 合并并 closes Issue。
- `/Applications/Kaji.app` 安装、签名与启动验证通过。
- companion human-smoke 已在 Lisa board 等待用户反馈。

Rollback：

- Settings 关闭 AI News 立即停任务并移除 UI。
- 新 prefs/cache 使用独立 key/file，旧版本忽略。
- 删除 `ai-news-cache-v1.json` 可安全回到首次加载。
- 若线上合同异常，可回滚 PR；不影响 Quota/Work/System/Goals 数据。

