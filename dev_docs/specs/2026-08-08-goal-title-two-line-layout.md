# Change Note: Goal 标题两行静态展开

Status: approved

## 类型

Primary: bug fix  
Secondary: UX polish  
Upstream: [2026-08-01-goals-surface-v2.md](./2026-08-01-goals-surface-v2.md)

## Goal

让 Today、Week 与 Vision 的两行 Goal 标题在未点击编辑时也立即完整显示，不再等获得焦点后才展开。

## In / Non-goals

覆盖未完成 Goal 与 Vision 的可编辑标题，最多显示两行；保留单行紧凑高度与现有编辑、完成、删除行为。不增加第三行，不改字体、按钮、数据或迁移。

## Behavior + decisions

- 自然折行或显式换行需要两行时，未聚焦状态即按两行布局。
- 聚焦与失焦不改变标题行数或造成高度跳变。
- 超过两行仍截断，Today、Week、Vision 使用同一规则。

## Acceptance

| Case | Given | Expected | Verify |
| --- | --- | --- | --- |
| T1 | Today / Week 两行标题未聚焦 | 两行立即可见 | 人工 smoke |
| T2 | Vision 两行标题未聚焦 | 两行立即可见 | 人工 smoke |
| T3 | 两行标题聚焦再失焦 | 行高稳定 | 人工 smoke |
| T4 | 单行与超过两行标题 | 单行紧凑；最多两行；按钮不挤出 | 人工 smoke |
| T5 | 项目构建与模型测试 | 无回归 | 自动：`swift test`、release build |

## Done + rollback

`swift test` 与 release build 通过；Light / Dark 人工抽查 Today、Week、Vision。回滚仅撤销布局测量，不涉及数据。

## 批准前必读

- **最多两行。** 更长标题仍截断，以保持页面紧凑。
- **覆盖 Today、Week、Vision。** 三处必须一致。
- **主要风险是行高抖动。** 必须人工检查未聚焦、聚焦、失焦。
