# Polish Spec：Settings Information Architecture

## 问题

Settings 使用 `AI` 同时指代 quota provider 与 AI News，导致页面标题重复，且
`1h / 3h / 5h / 12h / 24h` 的新闻刷新设置容易被误解为 quota 刷新。Goals 页面
又承载 Schedule 内容维护，混淆“偏好设置”与“日常内容管理”。

## 决策

- 侧栏不使用总括性的 `AI`。
- 独立提供 `Quota` 与 `AI News` 两个分类。
- `Quota` 只管理 provider 是否显示；不暴露当前固定 30 秒的内部采样周期。
- `AI News` 只管理 AI HOT 新闻刷新周期，保留现有小时级选项和默认 5 小时。
- `Goals` 分类保留，作为未来 Goals 行为偏好的稳定位置；当前内容清空。
- Today、Week、Vision、Schedule 的创建和维护留在 Goals 产品表面，不放 Settings。

## 验收

- 侧栏依次可见 General、Modules、Work、Goals、Quota、AI News。
- 页面内不出现重复的孤立 `AI` 标题。
- Provider 显示开关只出现在 Quota。
- 小时级刷新选项只出现在 AI News。
- Goals 页面不显示 Schedule 编辑器，也不删除现有 Goals 数据。
- 现有偏好键及读写兼容性不变。

## 非目标

- 不改变 quota 的 30 秒内部刷新机制。
- 不改变 AI News 的刷新策略、缓存或 API。
- 本轮不定义新的 Goals 偏好。
