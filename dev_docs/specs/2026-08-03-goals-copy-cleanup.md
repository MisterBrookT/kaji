# Spec: Goals 解释文案减法

Status: approved

## Goal

Goals 只保留有操作意义的名称、数字与内容，删除重复解释产品结构的副标题。

## In

- Goals 顶部删除 `Flexible · Fixed · Vision`。
- Vision 标题旁删除 `长期方向`。
- Fixed 行删除 `固定计划 · n 项`；右侧详情图标继续表达可展开。
- 非 Goals 页面原有必要状态文字不受影响。

## Non-goals

- 删除 Today、Week、Vision 标题。
- 删除热力图数字、完成数或 Fixed 详情。
- 改变数据模型。

## Acceptance

| Case | Expected | Verify |
| --- | --- | --- |
| C1 | Goals 标题下无副标题与空白占位 | 人工 smoke |
| C2 | Vision 标题行只显示 `Vision` 与添加按钮 | 人工 smoke |
| C3 | Fixed 行只显示计划名、Tag、完成状态、详情图标 | 人工 smoke |

## Done

Light / Dark Goals smoke 通过；无解释文案残留。

## Rollback

纯视图改动，可单文件恢复。

## 批准前必读

- 删除的是结构说明，不是状态信息；完成数与热力图保留。
- Fixed 的内部项数移入二级 popover，不再常驻主列表。
