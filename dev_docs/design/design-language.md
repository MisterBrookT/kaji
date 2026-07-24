# Kaji Design Language

黑白灰。就这一套。

跟随系统 Light / Dark。不要蓝、不要绿、不要橙。菜单栏工具该有的安静，不要 dashboard 感。

## Palette

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| Background | `#F8F8F6` | `#121212` | 底 |
| Background top | `#FFFFFF` | `#191919` | 轻微渐变顶 |
| Surface | `#FFFFFF` | `#202020` | 卡片 / 控件 |
| Text | `#20201D` | `#F0F0EC` | 主文字 |
| Secondary | `#70706A` | `#A0A09A` | 次要文字 |
| Faint | `#B2B2AC` | `#62625D` | 禁用 / 更淡 |
| Track | `#E5E5E1` | `#333330` | 环轨道 |
| Value | `#666660` | `#D2D2CC` | 正常用量弧 |
| Warning | `#3D3D39` | `#F0F0EC` | 接近上限 |
| Accent | `#666660` | `#D2D2CC` | 选中 / 小点（同 Value） |

## Rules

- 只做黑白灰。不恢复 Calm / Playful / Color 主题。
- Light / Dark 跟系统，不另搞一套外观开关。
- Track 保持中性灰，整环不要染色。
- Warning 只用于真压力（约 ≥80%）。
- 不要装饰渐变、光晕、营销色。
- 圆角小、对比安静、信息密但可读。

## 代码债（后做）

`Palette.swift` 里还有 Calm / Playful，Settings 还有 Black/White vs Color。产品已定：**删掉 Color 路径**，只留 Mono Light/Dark。

## Mood

原生菜单栏工具：一眼、低饱和。不是仪表盘，是可信信号。
