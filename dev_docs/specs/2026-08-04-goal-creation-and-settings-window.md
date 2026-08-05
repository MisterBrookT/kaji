# Spec: Goals 创建流程与标准设置窗口

Status: approved for implementation

## 问题

Goals 的 `+` 目前直接插入空白行。标签只能在创建后通过行内菜单修改，Vision 与 Fixed 也分散在不同入口。设置窗口把全部内容塞进 360pt 狭长栏，Fixed 编辑器还会横向扩展窗口，继续增加设置时难以浏览。

## 目标与范围

- Goals 使用一个紧凑创建 popover。可选择 Today、Week、Vision 或 Fixed。
- 创建 Today、Week、Vision 时，在保存前填写标题并选择现有 `GoalTag`。
- 创建 Fixed 时，复用 `FixedDayPlan`：选择星期、标题、Tag，并填写固定事项；保存后替换该星期模板。
- 设置改为标准矩形窗口：左侧分类，右侧滚动内容；至少包含 AI。
- 所有现有设置仍可访问并沿用原 `Prefs`、`FixedPlanStore`、`SleepController` 数据。

## 术语与数据

- “标签”是 `GoalTag` 的 Work、Health、Home、Learn、Admin、Personal 六个固定类别。现有规格明确不做自由文本、多 Tag 或全局 Tag 管理；本切片不扩张模型。
- “长期”存储为 `GoalHorizon.longTerm`，产品展示语义为 Vision。
- “Fixed plan”存储为每星期一天一份的 `FixedDayPlan`；每日完成状态仍由 `FixedPlanStore` 单独保存。创建 Fixed 不生成 `GoalItem`。
- Today、Week、Vision 仍保存为 `GoalItem`，不改变 JSON schema 或迁移版本。

## 关键交互

- Goals 顶部只有一个主“新建”入口；Today、Week、Vision、Fixed 不重复显示局部 `+`。
- 创建 popover 直接锚定主入口，旁侧相邻展开；点击打开后不会因鼠标跨越空白区域而失焦。`⌘N` 可从 Goals 页打开。
- 创建面板允许切换目标类型；非 Fixed 显示标题与 Tag，Fixed 额外显示星期和“事项 | 说明”多行输入。
- 标题去除首尾空白后为空时不可保存。取消不写入任何数据。
- Fixed 保存到已存在星期时，明确采用现有“一星期一天一份模板”约束，覆盖该星期模板内容。
- 设置侧边栏自然分为 General、Modules、Work、Goals、AI；Work、Goals 即使模块关闭仍可进入，模块开关继续由 Modules 控制。
- General 不再提供可变 popover Size 或 Pet 展示块；popover 使用单一标准尺寸。Prevent Sleep 回到 General 并显示真实状态和失败提示。
- Settings 的 System 分类即使模块未启用也显示明确状态、启用入口和只读磁盘扫描摘要，不允许空白页。
- 窗口默认约 760×560，可缩到 640×460；内容不足时右侧滚动。

## 状态与兼容

- 不新增或重命名 UserDefaults key。
- 不改变 Goal、Fixed 或 Prefs 编码格式。
- 标签仍通过 `GoalTag.rawValue` 保存；旧空 Tag 的关键词迁移逻辑保持。
- Fixed 每日完成状态不因编辑模板而清除。
- 设置分类选择仅为窗口会话状态，不持久化。

## 验收标准

1. Goals 只有一个主创建入口；点击或按 `⌘N` 打开与按钮相邻的创建面板。
2. 保存前可选择六种 Tag；保存、重启、展示均与现有行内 Tag 一致。
3. 可从同一面板创建 Vision，数据进入 `longTerm` 且无完成态 UI。
4. 可从同一面板设置某星期 Fixed，标题、Tag、事项写入现有 `FixedPlanStore`，Goals 当天展示与设置编辑器一致。
5. 空标题无法保存；取消不产生空白项目。
6. 设置以矩形窗口打开，侧边栏含 General、Modules、Work、Goals、AI。
7. 原模块、外观、系统、Work、Provider、Fixed 设置均可读写；过时 Size 与 Pet 展示块除外。
8. `swift test` 与 `swift build` 通过；人工 smoke 检查小窗口滚动和 Light/Dark Mono。

后续 smoke 修订：过时 Size 与 General Pet 展示已移除；宠物桥内部固定选择继续保留，不作为用户设置。设置窗口使用原生标题栏，不对 content view 做顶部圆角裁切。

## 非目标

- 自由文本 Tag、Tag 新建/删除、筛选、多 Tag。
- 多套 Fixed 模板、云同步、提醒、日期范围或 Vision 里程碑。
- 重做 Goals 主面板、菜单栏统计或 Fixed 完成语义。
- 新主题、设置搜索、Toolbar 或远程插件市场。

## System：磁盘空间洞察与建议清理

### 定位与信息架构

System 不再以 CPU、内存和进程监控为主入口，改为偶尔主动查看的“磁盘空间”页：

1. 卷总量、已用、可用空间和使用比例。
2. 用户可访问的常见目录占用排行：Downloads、Documents、Desktop、Movies、Pictures、Music、Caches。
3. 值得复核的候选项：大体积下载文件、缓存与开发构建产物。每项必须显示大小、路径类别和入选原因。
4. 操作仅为刷新扫描和在 Finder 中显示，由用户在系统界面自行决定清理。

### 扫描与性能

- System 模块启用时启动扫描；进入页面或点击刷新可立即扫描。
- 自动扫描最多每 30 分钟一次，不做 5 秒级磁盘遍历。
- 文件枚举在 utility 后台任务执行；跳过 package descendants、符号链接和不可读项。
- 初版只扫描当前用户的常见目录，不扫描其他用户、外接卷、网络卷、Mail、Photos Library 内部或整个系统盘。
- 目录占用为“当前权限可见大小”，不宣称等于 macOS Storage Management 的系统级统计。

### 可信解释、隐私与权限

- 所有扫描在本机执行，不上传文件名、路径或大小。
- 不读文件内容，只读取目录项元数据、大小和修改日期。
- 未获得 Full Disk Access 时走无需授权的安全路径；受保护或不可读目录计入“扫描受限”，UI 明示结果可能不完整。
- 候选规则可解释：缓存/构建产物说明“应用或工具可重新生成”；Downloads 大文件说明“体积较大且位于下载目录”，不推断文件无用。

### 安全约束与用户操作

- Kaji 不静默删除，不自动清理，不终止进程，不调用内存 purge。
- 本切片不提供应用内删除按钮；候选项只能“在 Finder 中显示”。
- `autoCleanEnabled` 旧偏好保留以兼容旧版本，但新 UI 不暴露且运行时不执行删除。
- 空状态区分“扫描中”“没有高价值候选”“扫描结果受权限限制”；失败时保留上次成功结果并允许重试。

### System 验收

1. 展示根卷总量、已用、可用和比例。
2. 展示至少一个可读常见目录的占用；按大小排序。
3. Downloads 中满足阈值的大文件或已知缓存/构建目录能成为候选，并显示原因。
4. 点击候选项可在 Finder 中定位，不改动文件。
5. 不可读目录不导致崩溃，UI 显示扫描受限。
6. System 关闭时停止周期扫描；启用后恢复。
7. 代码路径不存在自动删除、自动 kill 或自动 purge 的调用。
