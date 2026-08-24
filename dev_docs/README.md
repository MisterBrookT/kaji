# Internal docs (`dev_docs`)

维护者与 agent 的长期决策库，不是功能流水账，也不是公开文档站。

只保留四类内容：

- 产品方向与架构选择；
- 稳定的设计语言；
- 外部系统契约；
- 发布与分发约束。

已落地 feature、bug fix、单次 UI 调整和逐版本 release notes 不在这里存档；行为以代码与测试为准，版本变化由 GitHub Releases 自动生成。

## Catalog

### Product

| Doc | Decision |
| --- | --- |
| [product/vision.md](product/vision.md) | Kaji 在 AI 时代的长期位置 |
| [product/lean-module-host.md](product/lean-module-host.md) | 小而美优先、能力可裁剪 |
| [product/architecture-modules.md](product/architecture-modules.md) | 模块主机边界与增量演进 |
| [product/2026-08-05-popover-visualization-decision.md](product/2026-08-05-popover-visualization-decision.md) | Popover 与圆环的可视化架构选择 |
| [product/2026-08-08-mail-brief-executor-adr.md](product/2026-08-08-mail-brief-executor-adr.md) | Gmail、Codex 与本地数据的执行边界 |

### Design

| Doc | Decision |
| --- | --- |
| [design/design-language.md](design/design-language.md) | 黑白灰 Mono 视觉语言 |
| [design/palette.html](design/palette.html) | 视觉 token 参考 |

### Integrate

| Doc | Contract |
| --- | --- |
| [integrate/pet-bridge.md](integrate/pet-bridge.md) | `pet-state.json` bridge |
| [integrate/sleep-helper.md](integrate/sleep-helper.md) | Sleep helper 边界 |
| [integrate/localization.md](integrate/localization.md) | 本地化约束 |

### Ship

| Doc | Constraint |
| --- | --- |
| [ship/distribution.md](ship/distribution.md) | 安装、签名、Gatekeeper 与发布链 |

### Assets

[`assets/`](assets/) 只存 README 与设计决策仍引用的图像资源。

## Layout

```text
dev_docs/
  README.md
  assets/
  product/
  design/
  integrate/
  ship/
```

No public Pages landing — repo face is README + GitHub Releases.
