# Spec: Goals Schedule、可选说明与四种符号标签

Status: approved

## 类型

Primary: feature revision  
Secondary: data migration、UX simplification

## Goal

用户能用统一 Goal 模型创建多星期重复的 Schedule，并为任意 Goal 添加可选说明，同时用四种无文字符号形成安静、可辨识的标签语言。

## In

- UI 与产品术语将 `Fixed` 改为 `Schedule`。
- 一个 Schedule 可多选星期日到星期六，至少选择一天。
- 允许多个 Schedule 在同一天生效。
- Today、Week、Vision、Schedule 都支持可选说明。
- 有说明的 Goal 行显示安静提示；hover 时在相邻侧边 popover 查看完整说明。
- 新建与编辑只提供四种 Tag：Work、Home、Health、Personal；界面只显示符号，不显示 Tag 文字。
- 旧 Learn / Admin 数据继续可读，分别按 Work / Personal 显示，不做破坏性迁移。
- 迁移现有 `FixedDayPlan`、事项和当天完成状态。

## Non-goals

- 不做日期区间、具体时间、提醒、通知、日历同步或复杂 recurrence rule。
- 不做 Schedule 子任务或逐项完成。
- 不新增自由 Tag、多 Tag、Tag 颜色或自定义 icon。
- 不把说明做成富文本、附件、链接预览或 Markdown 编辑器。
- 不在 Settings 展示 Today / Week / Vision；Settings 只保留 Schedule 模板配置。

## Behavior + decisions

### 统一 Goal 字段

Today、Week、Vision、Schedule 共享：

- 标题：必填。
- Tag：现有六类之一。
- 说明：可选 multiline；空白 trim 后按无说明保存。

Schedule 额外拥有 `weekdays: Set<Int>`，使用现有 Calendar weekday 值 `1...7`。

创建面板不再出现“每行：事项 | 说明”与 TextEditor 语法。改为明确的“说明（可选）”输入；只有 Schedule 显示星期多选。

### Schedule

- `Schedule` 是重复 Goal，不是每日唯一模板。
- 创建时星期使用独立 toggle chips，可同时选择多天；全不选时保存禁用。
- 同一天可出现多个 Schedule。
- Today 展示当天匹配的所有 Schedule；每个 Schedule 独立完成。
- 完成状态按 `dayKey + scheduleID` 保存，跨日重置，不改变模板。
- Settings → Goals 只维护 Schedule：创建、编辑标题 / Tag / 说明 / 星期、删除。

### Notes

- 创建四类 Goal 时均可填写说明。
- 已有 Goal 可在行内辅助入口编辑说明，不常驻展开大输入框。
- 无说明时不显示占位图标。
- 有说明时显示一个低权重 `text.alignleft` 提示。
- hover 提示后打开紧邻行右侧的 popover；鼠标可直接进入。点击提示可固定打开，点击外部关闭。
- 说明不参与完成数、排序、热力图或菜单栏。

### Tag icons

可选 Tag 收敛为：

| Tag | 图形 |
| --- | --- |
| Work | 矩形 outline |
| Home | 矩形 half-fill |
| Health | 圆 outline |
| Personal | 圆 half-fill |

- 形状与内部填充共同表达 Tag；创建器、选择菜单与所有 Goal 行必须显示同一个小尺寸标记，不显示重复文字。
- 完成状态只改变为强调色，不覆盖 Tag 自身的内部设计。
- Learn 兼容为 Work 标记，Admin 兼容为 Personal 标记；一旦用户重新选择则保存为四种新值之一。
- 不用实心、三角、星、菱形、六边形，不使用多色区分。

## 数据与迁移

新增 `ScheduledGoal`：

- `id: UUID`
- `title: String`
- `tag: String`
- `note: String`
- `weekdays: Set<Int>`

`GoalItem` 新增可选兼容字段 `note`，旧 JSON 缺失时解码为 `""`。

迁移现有 Fixed：

1. 每个 `FixedDayPlan` 迁移为一个单星期 ScheduledGoal。
2. 标题、Tag 保留。
3. 原 `items` 按“标题 · dose”逐行合并到 note，内容不丢失。
4. 当前日 `isTodayCompleted` 映射到当前星期迁移出的 Schedule ID。
5. 使用独立 migration version，重复启动不重复导入。
6. 旧 Fixed keys 暂不删除，供回滚读取。

## Acceptance

| Case | Given | Expected | Verify |
| --- | --- | --- | --- |
| S1 | 创建 Schedule | 可多选星期；未选星期不能保存 | 自动逻辑 + 人工 |
| S2 | 一个 Schedule 选三天 | 仅三天的 Today 出现，同一 ID / 内容 | 自动 |
| S3 | 同一天有多个 Schedule | 全部出现，可独立完成 | 自动 + 人工 |
| S4 | 跨日 | Schedule 模板保留，完成状态按新日期为空 | 自动 |
| S5 | UI 文案 | 所有入口只称 Schedule，不出现 Fixed | 静态检查 + 人工 |
| N1 | 创建任意四类 Goal | 均可填可选说明；重启保留 | 自动 Codable + 人工 |
| N2 | 说明为空 | 行内不显示说明提示 | 人工 |
| N3 | hover / click 有说明 Goal | 相邻展示完整说明；鼠标可进入且不意外消失 | 人工 |
| N4 | 说明存在 | 不影响计数、排序和热力图 | 自动 |
| I1 | 新建 / 编辑 Tag | 只显示四个无文字符号：圆 / 矩形的 outline / half-fill | 自动映射 + 人工 |
| I2 | Goal 完成 | 保留原标签设计，仅改变强调色 | 人工 |
| I3 | 旧 Learn / Admin | 继续显示，分别兼容为 Work / Personal 标记 | 自动 |
| M1 | 旧 Fixed 数据 | 七天模板、Tag、事项文字无损迁移 | 自动 fixture |
| M2 | 旧今日 Fixed 已完成 | 对应迁移 Schedule 今日完成 | 自动 |
| M3 | 重复启动 | 不重复迁移 | 自动 |
| B1 | 旧 Goal JSON 无 note | 正常解码为无说明 | 自动 |
| R1 | 回归 | tests、debug/release build、bundle 签名通过 | 自动 |

## Test map

- `ScheduledGoalModelTests`：S1–S4。
- `GoalHorizonModelTests`：N1、N4、B1。
- `GoalIconStyleTests`：I1。
- `ScheduleMigrationTests`：M1–M3。
- 静态术语检查：S5。
- 人工 smoke：S1、S3、N1–N3、I1–I2。

## Likely file touch list

- `Sources/KajiCore/GoalHorizonModel.swift`
- 新增 `Sources/KajiCore/ScheduledGoalModel.swift`
- `Sources/Kaji/DailyGoalStore.swift`
- `Sources/Kaji/FixedPlanStore.swift`（迁移桥后逐步退场）
- `Sources/Kaji/KajiPopoverView.swift`
- `Sources/Kaji/SettingsView.swift`
- `Sources/Kaji/AppDelegate.swift`
- `Tests/KajiTests/`

此切片有数据迁移，但 acceptance 和顺序清楚；批准后 tests → migration/model → UI，不另写 plan。

## Done

- 全部 acceptance 有自动或人工验证。
- 自动测试、debug/release build、bundle 签名通过。
- 重装 `/Applications/Kaji.app` 后人工 smoke。
- 不 commit、不 push、不 tag，等待 smoke 确认。

## Rollback

- 旧 Fixed keys 保留；回滚版本继续读取旧模型。
- 新 Schedule keys 独立，旧版本忽略。
- `GoalItem.note` 为向后兼容字段，旧版本忽略未知字段。
- 安装失败恢复旧 `.app`。

## 批准前必读

- **Schedule 允许同一天多个重复 Goal。** 这正式替代“每天唯一 Fixed plan”；否则多选星期只能复制模板，后续编辑会产生难懂分叉。
- **旧事项不再是结构化子项。** 迁移时合并进说明，文字不丢，但不再单独编辑 dose；换来四类 Goal 一致模型。
- **说明只辅助上下文。** 不进入统计或主视觉，避免 Goals 膨胀成项目管理器。
- **旧六类数据可继续读取，但新 UI 只提供四种选择。** Learn / Admin 分别兼容到 Work / Personal；不批量重写用户数据。
