# Change Note: 磁盘单位与建议区收口

Status: approved

## 类型

Primary: change note  
Secondary: UX simplification

Upstream: [2026-08-04-goals-entry-and-daily-disk-insights.md](./2026-08-04-goals-entry-and-daily-disk-insights.md)

## Goal

System 磁盘视图使用稳定易读的 GB / MB 单位，并删除含义模糊、价值不足的“建议复核”区域。

## In

- 所有磁盘大小使用十进制 GB / MB。
- 大于等于 1 GB 显示 GB；小于 1 GB 显示 MB。
- 删除“建议复核”标题、候选列表、Finder 定位入口和候选扫描。
- 保留卷总览、文件类型分类、扫描状态、时间、权限限制与手动刷新。

## Non-goals

- 不新增清理建议、删除能力或 Finder 操作。
- 不改变 24 小时缓存策略和扫描边界。
- 不改变文件类型分类规则。

## Behavior + decisions

- `1 GB = 1,000,000,000 bytes`，`1 MB = 1,000,000 bytes`。
- GB 保留最多一位小数，整数不显示 `.0`。
- MB 四舍五入为整数；非零且不足 1 MB 显示 `1 MB`。
- 总容量、已用、可用、分类行全部调用同一个 formatter。
- 移除候选生成可减少不必要的路径存储和扫描判断。

## Acceptance

| Case | Given | Expected | Verify |
| --- | --- | --- | --- |
| U1 | 16,980,000,000 bytes | `17 GB` | 自动 |
| U2 | 1,250,000,000 bytes | `1.3 GB` | 自动 |
| U3 | 980,000,000 bytes | `980 MB` | 自动 |
| U4 | 500,000 bytes | `1 MB` | 自动 |
| U5 | System UI | 所有大小格式一致 | 人工 |
| C1 | 打开 System | 不存在“建议复核”或候选列表 | 静态检查 + 人工 |
| C2 | 扫描 | 不生成或持久化清理候选路径 | 自动模型 / 静态检查 |
| R1 | 回归 | tests、build、签名通过 | 自动 |

## Done

- formatter 测试通过。
- System smoke 无建议区。
- 不 commit、不 push、不 tag，等待 smoke 确认。

## Rollback

- formatter 为纯显示逻辑，可独立回滚。
- 缓存解码忽略旧候选字段；不影响文件分类数据。

## 批准前必读

- **建议区完整删除，不改名。** 当前没有足够可信度支撑“值得清理”的判断。
- **统一使用十进制单位。** 数字会与 Finder 更接近，但可能与二进制工具显示略有差异。
