# Calm Break

状态：**Approved（2026-07-31）**

## Goal

把强制休息从“宠物拦截 + 动作任务”改成安静、会轻微呼吸的日系自然场景。

## In

- 全屏休息页移除熊猫及 fallback 绘图。
- 移除推荐动作卡片、动作轮播、待办目标条与命令式文案。
- 内置四张同一视觉语言的日系自然场景：窗边小雨、雨中田野、薄雾山坡、晴日林间田野。
- 每次进入休息随机选一张；同一次休息不换图。
- 场景使用慢速位移/缩放，并以原生绘制加入雨丝、草浪或薄雾。
- Reduce Motion 开启时完全静止。
- 保留倒计时与可选 Skip；信息层使用黑白灰 Mono 半透明材质。
- 多屏展示同一场景；只有主屏显示操作。

## Non-goals

- 不做桌面 Widget。
- 不加入宠物或运动动作的新替代玩法。
- 不做视频、声音、天气联动、在线壁纸或场景商店。
- 不把休息页变成目标或配额 dashboard。
- 不改变 Work / Break 时序、全屏阻断层级或现有安装方式。
- 不发布、不 tag；完成后先本地 smoke。

## Behavior + decisions

时序保持 `breakDue → breaking → 倒计时结束自动关闭`。Hard Break 仍是 Work 模块下的显式开关。

主屏构图为全屏自然图、轻微动态层、中央偏下的倒计时与可选 Skip。文案固定为：

- 标题：`休息一下`
- 副文案：`离开屏幕片刻。`
- 进行中不展示 Skip 次数。

自然图作为 app bundle 本地资源提交，不依赖网络。画面采用克制的日系动画电影背景感，低饱和、无人物/动物/文字。雨丝、草浪、薄雾、林间光斑只做慢速局部运动，不做闪电、强风或高频变化。

## Acceptance

| Case | Given | Expected | Verify |
| --- | --- | --- | --- |
| B1 | Hard Break 开且 focus 到点 | 全屏自然场景 + 倒计时；无熊猫、动作卡、目标条、命令式文案 | 自动：资源/模型；人工 smoke |
| B2 | 同一次休息持续中 | 场景不切换，仅缓慢运动 | 自动：selection model；人工 smoke |
| B3 | Reduce Motion 开启 | 场景及动态层静止，倒计时正常 | 自动：motion policy；人工 smoke |
| B4 | 双屏进入休息 | 两屏场景一致，仅主屏可操作 | 自动：selection model；人工 smoke |
| B5 | 允许 Skip 关闭 | 页面不出现 Skip | 回归测试 + 人工 smoke |
| B6 | Work 或 Hard Break 关闭 | 不出现 overlay，倒计时行为不回归 | `swift test` + 人工 smoke |
| B7 | 四个场景资源随 app 打包 | 每个场景均能读取，缺失时仍有安静的 Mono fallback | 自动：资源清单；release bundle smoke |
| R1 | 完整回归 | 核心测试与 release build 通过 | `swift test`、`swift build -c release`、bundle validation |

## Test map

- `BreakSceneModelTests`：场景集合、一次休息固定选择、Reduce Motion policy。
- 现有模块与 Work 状态测试负责开关、倒计时回归。
- 人工 smoke：三种场景、正常/Reduce Motion、双屏、Skip 开关。

## Likely touch list

`BreakOverlayView.swift`、`AppDelegate.swift`、`Sources/KajiCore/`、自然场景资源、打包脚本与测试。

## Done

- 所有 Acceptance 自动项通过。
- 本地构建可读三张自然场景。
- 用户完成休息页 UX smoke 并确认。
- 未经确认，不 commit / push / tag / release。

## Rollback

- 回退 Calm Break view、场景 model 与三张资源。
- Work session 数据不迁移，回退不影响配置或历史。

## 批准前必读

- **休息页仍是全屏 Hard Break。** 去掉熊猫和动作命令，但不削弱覆盖层级。
- **自然画面是四张日系雨景/田野静态图 + 原生轻动画。** 包含一幕晴日林间田野；离线、安静、体积可控，并正确支持 Reduce Motion。
- **桌面 Widget 已取消。** 本切片不再触碰 `.appex`、App Group、签名或安装策略。
