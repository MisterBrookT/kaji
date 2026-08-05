# Spec: Goals 入口收紧与每日磁盘洞察

Status: approved

## 类型

Primary: feature revision  
Secondary: UX polish、performance

Settings 保持配置面板，不承载 Goals 浏览或磁盘扫描。本轮的产品行为变化只发生在 Goals popover 与 System module。

## Goal

Goals popover 去掉创建入口造成的多余留白，System module 用每日缓存的文件类型洞察提供更清楚、低成本的磁盘视图。

## In

- Goals 唯一“新建”按钮移入“今天”标题行。
- System module 增加按文件类型聚合的空间可视化。
- System 自动扫描最多每天一次，支持手动刷新，复用上次成功缓存。
- Settings 删除冗余解释文案，仅保留真正配置；必要说明改为 hover。
- Settings 侧栏继续显示所有配置分类，但不展示 Goal 列表、热力图或磁盘扫描结果。

## Non-goals

- Settings 不成为模块 dashboard，不浏览 Today、Week、Vision 或磁盘占用。
- 不改变 Module 开关语义：关闭仍隐藏模块 surface，并停止该模块 timers / polls。
- 不新增 Goal 数据模型、自由 Tag、提醒或云同步。
- 不扫描文件内容，不上传数据，不自动删除，不 kill，不 purge。
- 不模拟 macOS Storage Management 的全盘权威统计。

## Behavior + decisions

### Surface responsibilities

- Menu bar：最短状态。
- Popover module：查看状态、当前动作和紧凑维护。
- Settings：偏好、开关和模板配置。

Settings → Goals 只保留 Fixed weekly template 等配置型内容，不复制 Today / Week / Vision 和热力图。

Settings → System 不启动扫描、不显示磁盘 dashboard。System 相关配置没有实际选项时，可不提供独立内容页；模块开关留在 Modules。

### Goals entry

- “今天”行顺序为：标题、完成数、弹性空间、唯一“新建”按钮。
- 删除标题上方独立创建 HStack 及其垂直间距。
- “新建”仍可创建 Today、Week、Vision、Fixed，直接锚定创建 popover。
- Week、Vision、Fixed 不恢复局部加号；保留 `⌘N`。

### System file categories

System module 的卷空间总览下显示 mono 分类图例与大小：

- Apps / Developer
- Video
- Images
- Audio
- Documents
- Archives
- Caches
- Other

分类只使用扩展名、已知目录和文件大小。Other 接住未知类型。候选建议继续解释原因，唯一操作是在 Finder 中显示。

### Scan schedule

- 没有成功缓存，或缓存距今至少 24 小时，进入 System module 后才后台扫描。
- 24 小时内反复打开 popover、切换 module 或重启应用，不重新扫描。
- 用户点击刷新可强制扫描。
- 不保留 30 分钟扫描 timer；System disabled 时不扫描。
- 扫描成功结果写入独立缓存：卷容量、类型汇总、主要目录、候选、受限计数、时间。
- 失败保留上次成功结果，同时显示失败状态。

### Settings copy

- 删除 Prevent Sleep 常驻解释段落，控件 `.help` 提供用途和授权说明。
- 删除 System 配置页里的扫描摘要和只读说明。
- 错误状态不能藏到 hover。

## 数据与兼容

- Goal、Fixed、completion 与 `enabledModules` 语义不变。
- 新增磁盘洞察缓存 key；损坏时忽略并重新扫描。
- Prevent Sleep 继续使用现有 `SleepController`。
- 旧 auto-clean 偏好不恢复执行。

## Acceptance

| Case | Given | Expected | Verify |
| --- | --- | --- | --- |
| G1 | 打开 Goals | “新建”位于“今天”行；其上无独立空行 | 人工 smoke |
| G2 | 点击“新建”或按 `⌘N` | 相邻 popover 可创建四类 Goal | 人工 smoke |
| G3 | 查看其他区 | Week、Vision、Fixed 没有局部创建按钮 | 人工 smoke |
| C1 | 存在常见类型 fixture | 分类大小正确，未知扩展进入 Other | 自动 |
| C2 | 分类结果展示 | 各类大小、占比和总量关系清晰 | 人工 smoke |
| D1 | 无缓存进入 System | 显示扫描中，成功后缓存结果 | 自动 + 人工 |
| D2 | 缓存小于 24 小时 | 直接显示缓存，不扫描 | 自动 |
| D3 | 缓存超过 24 小时 | 进入 System 后后台扫描一次 | 自动 |
| D4 | 点击刷新 | 强制执行一次扫描 | 自动 + 人工 |
| D5 | System disabled | 不运行扫描或 timer | 自动 |
| D6 | 扫描失败 / 缓存损坏 / 目录受限 | 不 crash；保留旧结果并显示状态 | 自动 |
| T1 | 打开 Settings | 没有 Goal dashboard 或磁盘 dashboard；现有配置仍可用 | 人工 smoke |
| T2 | hover Prevent Sleep | 显示用途 / 授权说明；页面无常驻长段落 | 人工 smoke |
| P1 | 静态检查 | System 无自动删除、kill、purge 路径 | 自动 |
| R1 | 完整回归 | tests、debug/release build、bundle 签名通过 | 自动 |

## Test map

- `DiskFileCategoryTests`：C1。
- `DiskInsightCacheTests`：D1–D6。
- 现有 module lifecycle tests：D5。
- 静态安全检查：P1。
- 人工 smoke：G1–G3、C2、D1、D4、T1–T2。

## Likely file touch list

- `Sources/Kaji/KajiPopoverView.swift`
- `Sources/Kaji/SettingsView.swift`
- `Sources/Kaji/SystemMonitor.swift`
- `Sources/Kaji/AppDelegate.swift`
- 新增纯逻辑分类 / 缓存模型于 `Sources/KajiCore/`
- `Tests/KajiTests/`

批准后 tests → code；无需独立 plan。

## Done

- Acceptance 全部有验证结果。
- tests、debug/release build、bundle 签名通过。
- 重装测试 bundle 后人工 smoke。
- 不 commit、不 push、不 tag。

## Rollback

- Goals 入口可回到当前独立行，不影响数据。
- 删除新缓存 key 即回到无缓存状态。
- 分类模型不写回用户文件；回滚不需要数据迁移。
- 安装失败恢复旧 `.app`。

## 批准前必读

- **Settings 只做配置。** 不复制 Goals 或 System 内容，避免多套 surface 争夺产品主入口。
- **Module 开关语义不变。** 关闭继续停止该模块扫描；不会为了 Settings 常显而改生命周期。
- **每日一次按“上次成功扫描 + 24h”判断。** 不是固定午夜任务；手动刷新例外。
- **文件类型结果只是当前权限可访问范围。** 必须显示扫描时间 / 受限状态，不能冒充系统全盘统计。
