# Spec: Goals Fixed 与 Vision

Status: approved

## Goal

Goals 统一承载 Flexible、Fixed、Vision；Fixed 是按星期生成的整体目标，Vision 是长期方向。

## In

- Flexible 保留 Today 与 Week，可添加、编辑、完成、删除。
- Fixed 每天按星期模板生成一个整体目标，内部事项只展示，不逐项完成。
- Fixed 模板在 Settings 侧栏按星期编辑；完成状态按日期保存。
- Fixed 悬停时从右侧打开紧凑的 anchored secondary popover。
- Vision 可添加、编辑、删除、排序，没有 checkbox 与完成统计。
- 菜单栏使用日历图标，完成数包含 Today Flexible 与当天 Fixed，不包含 Week、Vision。

## Data

- 现有 Today、Week、Long-term 数据原样保留。
- Long-term 在 UI 中按 Vision 语义展示，旧完成状态不参与统计。
- Fixed 模板与每日完成状态使用独立 UserDefaults key。

## Acceptance

| Case | Expected |
| --- | --- |
| Today 2 项、Fixed 未完成 | 今日与菜单栏显示 `0/3` |
| 完成 Fixed | 整体增加一个完成数，内部事项无 checkbox |
| 悬停 Fixed | 右侧二级 popover 出现，父 popover 不改变尺寸 |
| Vision 存在 | 可编辑、排序，不出现完成语义 |
| 重启 | Flexible Tag、Fixed 模板与今日完成状态保留 |

## Non-goals

- Fixed 内部事项逐项完成。
- Vision 里程碑、日期、提醒或进度。
- 多套固定计划、云同步、Tag 筛选器。
