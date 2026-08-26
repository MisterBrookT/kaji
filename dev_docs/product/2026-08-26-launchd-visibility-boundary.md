# launchd 可见性模块边界

## 决策

Kaji 的 Background Tasks 模块 v1 只读，并且默认关闭。它只观察当前用户的 GUI launchd 域，不提供启动、停止、卸载、重新加载或提权操作。

模块启用后，只在状态栏 popover 可见时执行一次 `launchctl list`，并读取 `~/Library/LaunchAgents` 中 plist 的 `Label`，把已安装但未出现在 GUI 域中的任务标为 `unloaded`。不为每个 label 调用 `launchctl print`，也不在 popover 关闭时保留定时心跳；禁用模块时立即停止刷新并清空模块状态。

## 信息层级

首先显示 running、failed、unloaded 三个汇总，让异常与不可见的未加载任务一眼可见。任务列表先显示用户安装的 LaunchAgents，再显示 GUI 域中的其他任务；每组内按 failed、running、idle、unloaded 排序，然后按 label 排序。

这不是 launchctl 的图形控制台。Kaji 只负责让后台活动变得可见，避免在混有系统更新器、第三方守护和 Kaji 自身任务的域里增加误操作风险。

## 后续门槛

只有在真实使用证明只读观察不足，并且能设计出明确的来源、风险提示与防误触机制后，才重新评估控制操作。system 域与 LaunchDaemons 不在本模块范围内。
