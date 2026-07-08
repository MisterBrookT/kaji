# Kaji 主页与预览图设计稿

## 设计判断

Reading this as: GitHub README / 产品主页，面向 AI coding 用户和 macOS 开发者，视觉语言走原生菜单栏工具、克制、可信、可爱但不幼稚。

推荐参数：

- `DESIGN_VARIANCE`: 5
- `MOTION_INTENSITY`: 2
- `VISUAL_DENSITY`: 5

Kaji 首页不要做大营销页。它应该像一个能马上安装的 macOS 工具：第一眼看到菜单栏入口、窄高 popover、Navi 熊猫、token 和休息状态。

## 首页结构

README 顶部保持当前结构：

1. 小 Navi 图标 + `Kaji` 居中。
2. 一句话：macOS menu bar command center for AI coding。
3. 一句价值：看 Claude Code / Codex 用量，管理休息节奏，必要时让 Navi 拦住工作。
4. 徽章：release / stars / macOS / license。
5. 一张强 hero 预览图。
6. Why / Install / What Kaji Does / Navi / Safety / Star History。

不要把功能截图铺成很多张。首屏一张强图比四张弱图更适合传播。

## Hero 预览图目标

一张图要说清三件事：

- Kaji 在菜单栏里，不是普通网页 dashboard。
- 它能看 AI coding 用量和成本。
- 它会用 Navi 做休息干预。

推荐文件：

- 输出：`docs/readme-hero-YYYYMMDD.jpg`
- 宽度：1600-1800 px 原图，README 中显示 `width="860"`
- 大小：目标 100-300 KB，最多别超过 600 KB
- 格式：JPG，用 CleanShot 拼好后压缩

## Hero 构图

推荐三层拼图：

### 1. 主画面

桌面背景保持干净，顶部保留真实 macOS 菜单栏。

主角是 Kaji popover：

- 使用 Mono 模式。
- 宽小于高。
- 打开 `Quota` 面板。
- 显示 Today tokens、Cost、Pressure。
- Codex / Claude Code 至少两行有数据。
- 趋势线要向上，避免看起来像没在用。

### 2. 侧面小卡

右侧或下方放一张小的 Work / Break 或 Goals 截图：

- Work / Break：显示 `45m / 2m` 或你真实偏好的节奏。
- Goals：显示热力图和当天完成数。

二选一即可。不要四个 panel 全部塞进去。

### 3. Navi

放一个小 Navi 熊猫作为视觉锚点：

- 可以在右下角，或靠近 break 小卡。
- 不要加消息框。
- 不要让熊猫遮挡数据。
- 如果展示强制休息，可以单独做第二张宣传图，不放 README 首图。

## CleanShot 截图建议

先准备环境：

1. 隐藏菜单栏里无关图标，只保留 Kaji、Wi-Fi、电池、时间等必要项。
2. 退出会弹通知的应用。
3. 用浅色桌面或非常干净的深色桌面，不要杂乱壁纸。
4. Kaji 设为 Mono，状态栏图标保持黑白灰。
5. 确保 Quota 有真实数据。不要出现假 0。

截图顺序：

1. 截一张菜单栏 + Quota popover。
2. 截一张 Work 或 Goals popover。
3. 截一张 Navi 静态状态。
4. 用 CleanShot 拼成一张，主图占 70%，小图占 30%。
5. 导出 JPG，再用 `sips` 或 ImageOptim 压缩。

可用命令：

```sh
sips -s format jpeg -s formatOptions 82 docs/readme-hero.png --out docs/readme-hero-YYYYMMDD.jpg
```

## 功能展示优先级

必放：

- Quota：今日 token、成本估算、压力、provider 行、趋势线。
- 菜单栏状态：证明这是 status bar app。
- Navi：证明产品有记忆点。

推荐：

- Work / Break：专注计时、休息时长、Skip。
- Goals：热力图和当天完成状态。

可选：

- System：CPU / Mem / Disk / Auto clean。
- Settings：除非要强调可配置，否则不放首图。

不建议首图展示：

- 全屏 break overlay。它适合单独做宣传图。
- 系统清理按钮太多的画面。
- 复杂设置页。
- 四个 panel 全铺开。

## 可参考项目

来自已沉淀的 Kaji 调研：

- Mole：统一入口，先扫描后操作。参考信息组织，不参考大而全感。
- LookAway：绿色健康感、休息预告、可延后。参考休息产品氛围。
- BreakTimer / Stretchly：工作间隔和短休息可配置。参考节奏模型。
- Stats：菜单栏系统指标要一眼可读。参考 CPU / 内存 / 磁盘表达。
- RunCat：宠物映射系统状态。参考“状态变成可爱行为”。
- Tokcat / Toki Monitor：AI coding token、成本、趋势线。参考 quota 首屏。

本地笔记：

- `01 Sources/kaji/2026-07-06-Kaji-Mole-状态栏参考.md`
- `03 Synthesis/kaji-gauge-competitor-scan-2026-06-27.md`
- `03 Synthesis/desktop pet market scan 2026.md`
- `docs/design-language.md`

## 避坑

- 不要用假网页 dashboard。
- 不要用 fake UI div 重新画 Kaji。
- 不要放大面积渐变、光晕、彩色泡泡。
- 不要让绿色进入菜单栏图标。绿色只用于 popover 主题。
- 不要为了填满高度制造空白。
- 不要让截图里出现无意义 `0`。
- 不要让按钮和底部导航抢主视觉。

## 第二张宣传图

发布小红书 / X / Product Hunt 时，可以做第二张图：

- 标题：`Navi blocks you when it is time to rest.`
- 画面：全屏 break overlay，中间大 Navi，旁边显示倒计时和 Skip。
- 目的：解释“强制休息但可跳过”。

README 首图负责讲产品全貌。第二张传播图负责讲记忆点。
