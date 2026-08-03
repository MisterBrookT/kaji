# Spec: Goals 单一状态与 legacy 清理

Status: approved

## Goal

Goals 只认 `goalHorizonStateV1`。删除旧 `dailyGoals*` 兼容路径，避免新状态缺失或损坏时重新导入陈旧任务。

## Load contract

- `goalHorizonStateV1` 有效：原样加载，不改写用户内容。
- 新状态缺失：创建空 Today / Week / Vision 状态并持久化，不读取旧数据。
- 新状态损坏或类型错误：保留原始数据与诊断信息，然后创建空状态；不得读取旧数据覆盖。
- 每次加载删除 `dailyGoals`、`dailyGoalsDayKey`、`dailyGoalsHistory` 与旧 migration marker。
- 后续重复启动只读取唯一新状态，不重复初始化或导入。

## Persistence

- loader 与 saver 放在 KajiCore，使用隔离 UserDefaults suite 做真实持久化测试。
- store 继续在 mutation 后保存；本切片不做 debounce 或 UI 重构。
- 跨日仍归档昨日完成率、移动未完成项并清空 Today。

## Diagnostics

- 损坏的 Data 保存到独立 backup key。
- 保存可读的诊断记录，包含错误类型；不显示用户内容。
- 本切片不删除 backup，不提供自动恢复 UI。

## Acceptance

| Case | Expected |
| --- | --- |
| 有效新状态首次加载 | Today / Week / Vision / history / IDs 原样保留 |
| 重复启动 | 状态一致，无默认项、无重复导入 |
| 仅 legacy 数据存在 | legacy keys 被删除，新状态为空 |
| 新状态损坏 | 原 blob 被备份，有诊断；新状态为空且可再次加载 |
| 新状态类型错误 | 有诊断；不 crash、不读取 legacy |
| 跨日 | 历史记录旧日统计，未完成项进入 Yesterday，Today 清空 |

## Non-goals

- 从 legacy 自动恢复。
- 删除 corrupt backup。
- 更改 Goals UI、Fixed、Pet、Quota 或 Break。
