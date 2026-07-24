<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**AI 时代还值得一直挂着的菜单栏。**

一眼看清额度压力，然后继续跑 agent。

[English](README.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260724.jpg" width="860" alt="Kaji 菜单栏弹窗" />

</div>

## 是什么

给 **AI coding 额度**用的 macOS 菜单栏应用（Claude Code / Codex 等）。菜单栏上的环显示 5h / 7d 用量和重置时间，跑飞之前能看见压力。

没有 dashboard，没有 Dock 图标。专注休息、系统负载、每日目标是可选模块——默认关，在 Settings 里按需打开。

`Kaji` 来自日语 `舵 / かじ`。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
```

需要 macOS 13+（Apple Silicon）、`git`、`swift`。拉取最新 release tag、本机构建、清 quarantine，装到 `/Applications`。

Release **不**附 `.app.zip`（未签名浏览器下载易被 Gatekeeper 拦）。也可 clone 后跑 `./scripts/build-local.sh`。

## 模块

| 模块 | 默认 | 能力 |
| --- | --- | --- |
| **Quota** | 开 | 5h / 7d 用量、重置、token 趋势、成本估算、provider |
| **Work / Break** | 关 | 专注计时、菜单栏倒计时、休息遮罩 |
| **System** | 关 | CPU / 内存 / 磁盘、顶部进程、保守的 Auto Reclaim |
| **Goals** | 关 | 每日目标 + 热力图 |
| **Pet** | 桥接 | 可选 Navi：`~/Library/Application Support/Kaji/pet-state.json` |

主题只有 **Mono**（黑白灰，浅色 / 深色）。

## 构建

```sh
swift test
./scripts/build-local.sh
```

## 链接

- [最新 Release](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md) — 贡献者 / agent 笔记
- [dev_docs/](dev_docs/README.md) — 内部 spec

## License

MIT. 见 [LICENSE](LICENSE)。
