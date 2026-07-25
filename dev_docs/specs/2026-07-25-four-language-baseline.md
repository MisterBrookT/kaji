# Kaji 四语基线

> **状态：Approved**
>
> 日期：2026-07-25

## Goal

Kaji 对全新用户默认使用 English，并把 English、简体中文、Português (Brasil)、Español 固定为今后所有用户界面的基础语言集合，同时完整保留现有用户已经选择的语言。

## In

- `Lang` 从两种扩展为四种：
  - English：`en`
  - 简体中文：`zh`
  - Português (Brasil)：`pt-BR`
  - Español：`es`
- 设置页语言行显示四个独立选项：`EN / 中文 / PT-BR / ES`。
- 点击语言选项后立即刷新设置页、popover、菜单和状态文案，并持久化选择。
- 全新安装固定默认 `en`，不再根据 macOS 首选语言自动选择。
- 升级迁移保留已有选择，并兼容旧安装没有 `language` key 的情况。
- 当前 `L10n.K` 全部提供四语文案。
- 今后新增用户可见文案，必须在同一变更中提供四语版本。
- contributor 文档写明四语规则、语言代码、默认值和迁移约束。

## Non-goals

- 不新增自动跟随系统语言模式。
- 不自动切换语言。
- 不添加繁体中文、葡萄牙葡语或西班牙地区变体。
- 不本地化产品名、供应商名、模型名、命令、路径、URL、`5h` / `7d` 等稳定技术标记。
- 不改已有用户其他偏好。
- 本次不重构为 `.strings` / String Catalog；保持当前轻量枚举表，避免扩大切面。
- 不发版。

## Behavior 与 locked decisions

### 1. 新安装

首次启动前不存在任何 Kaji 偏好标记时：

1. 语言设为 `en`。
2. 立即持久化 `language=en`。
3. 写入新的偏好初始化标记，供后续迁移判断使用。

macOS 系统语言不影响新安装默认值。

### 2. 已明确选择语言的老用户

若 `UserDefaults["language"]` 是已知旧值：

- `en` 保持 `en`。
- `zh` 保持 `zh`。

升级不得根据系统语言、App 新默认值或初始化标记覆盖它。

未来已存储的 `pt-BR`、`es` 同样原样恢复。

### 3. 没有 language key 的老安装

旧版本可能只在内存使用 `Lang.system`，未把首次推断结果写入 `language`。因此必须在 `Prefs.init()` 写入任何默认偏好前捕获 `hadExistingPreferences`：

- 若启动时 `language` 缺失，但任一既有 Kaji 偏好 key 已存在，判定为老安装。
- 按旧规则迁移一次：macOS 首选语言以 `zh` 开头则写入 `zh`，否则写入 `en`。
- 立即持久化结果；后续系统语言变化不得改变它。

此规则只用于兼容旧安装，不用于全新安装。

### 4. 未知或损坏的 language 值

若 `language` key 存在但不是 `en / zh / pt-BR / es`：

- 回退到 `en`。
- 写回 `language=en`。
- 不影响其他偏好。

### 5. 设置交互

- 语言行固定顺序：`EN`、`中文`、`PT-BR`、`ES`。
- 每项都是独立 segment；当前语言高亮。
- 点击已选项无副作用。
- 点击其他项立即持久化并重绘。
- 不再使用二态 `toggled` 循环。
- 语言名称保持自称，不随当前界面语言翻译。

### 6. 文案完整性

- `L10n` 每个 key 必须同时声明 `en / zh / ptBR / es`。
- 编译期结构应尽量阻止漏列；测试再枚举所有 key 和语言，拒绝空字符串。
- 葡萄牙语采用巴西葡萄牙语。
- 西班牙语采用中性西班牙语。
- 文案优先自然、短、适配现有紧凑布局，不做逐词直译。

## Acceptance 与 Verify

| ID | Given | Expected | Verify |
| --- | --- | --- | --- |
| A1 | 全新偏好域；macOS 为中文 | 首次语言仍为 `en`，并持久化 `language=en` | 自动测试：纯迁移逻辑；集成测试：隔离 UserDefaults |
| A2 | 老用户已有 `language=en` | 升级后仍为 `en` | 自动测试 |
| A3 | 老用户已有 `language=zh` | 升级后仍为 `zh` | 自动测试 |
| A4 | 老安装缺失 `language`，已有其他 Kaji key，系统中文 | 一次迁移为 `zh` 并持久化 | 自动测试 |
| A5 | 老安装缺失 `language`，已有其他 Kaji key，系统非中文 | 一次迁移为 `en` 并持久化 | 自动测试 |
| A6 | `language` 为未知值 | 回退并写回 `en`；其他偏好不变 | 自动测试 |
| A7 | 用户依次选择四种语言 | 选择立即持久化；重启后保持最后选择 | 自动测试持久化 + 人工 smoke |
| A8 | 打开设置页 | 同行显示 `EN / 中文 / PT-BR / ES`，当前项高亮，无截断或重叠 | 人工 smoke：Small / Medium、Light / Dark |
| A9 | 任一 `L10n.K` × 任一支持语言 | 返回非空文案 | 自动完整性测试 |
| A10 | 切换到每种语言浏览主要界面 | Settings、popover、菜单、状态与错误文案使用所选语言；产品/技术标记保持原样 | 人工 smoke |
| A11 | 已选语言后改变 macOS 首选语言并重启 Kaji | Kaji 语言不变 | 自动迁移测试 + 人工 smoke |

## Implementation touch list

- `Sources/Kaji/Prefs.swift`
  - 扩展 `Lang`
  - 删除二态 `toggled`
  - 实现新装/老装迁移
  - 扩展 `L10n` 四语表
- `Sources/Kaji/SettingsView.swift`
  - 四个明确语言 segment
- `Sources/KajiCore/`
  - 增加纯语言迁移逻辑，避免测试直接依赖全局 UserDefaults
- `Tests/KajiTests/`
  - 迁移矩阵、持久化、L10n 完整性
- `dev_docs/`
  - 四语 contributor 规则

规格清楚且触点集中；批准后跳过独立 plan，直接 tests → code → smoke。

## Done

- A1–A7、A9 自动测试全绿。
- 全仓库 `swift test`、debug/release build、app bundle 组装通过。
- A8、A10、A11 人工 smoke 通过。
- 用户确认 smoke 后，才允许 commit / push / PR。
- 不创建 tag，不发布 release。

## Rollback

- 代码回滚到两语 UI 时，不删除或重写已保存的 `language`。
- 若回滚版本无法识别 `pt-BR` / `es`，应安全显示 English；再次升级后恢复用户已选语言需要保留单独的原始选择 key。实现阶段必须确保回滚不会把原始四语选择永久覆盖。
