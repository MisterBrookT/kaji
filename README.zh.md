<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**AI 时代 Mac 上离个人最近的状态与控制层。**

今天真正重要的事情，一眼就够。

[English](README.md) · [Português](README.pt-BR.md) · [Español](README.es.md)

<a href="https://github.com/blackblue-labs/kaji/stargazers"><img src="https://img.shields.io/github/stars/blackblue-labs/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/blackblue-labs/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

<br />
<br />

<img src="dev_docs/assets/readme-hero-20260724.jpg" width="860" alt="Kaji 菜单栏弹窗" />

</div>

## 是什么

Kaji 把与你有关的活状态放进 **Menu Bar**。这些状态包括 AI quota、专注、Goals 和 Mac。

为什么是 Menu Bar？因为它始终在当前工作旁边：一眼知道状态，hover 获得上下文，点击立即操作。不需要切换 App，也不需要一条通知来打断你。

Kaji 默认很小。Quota 开启，其它 module 按需选择：一个壳，只留下你愿意放在身边的信号。

`Kaji` 来自日语 `舵 / かじ`。

[阅读 Vision](dev_docs/product/vision.md)。

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
| **System** | 关 | CPU / 内存、磁盘分类、顶部进程 |
| **Goals** | 关 | Today / Week / Vision / Schedule、说明、标签与热力图 |
| **AI News** | 关 | AI HOT Top 10、hover 摘要与来源信息 |
| **Pet** | 桥接 | 可选 Navi：`~/Library/Application Support/Kaji/pet-state.json` |

主题只有 **Mono**（黑白灰，浅色 / 深色）。

## 构建

```sh
swift test
./scripts/build-local.sh
```

## 链接

- [最新 Release](https://github.com/blackblue-labs/kaji/releases/latest)
- [AGENTS.md](AGENTS.md)：贡献者 / agent 笔记
- [dev_docs/](dev_docs/README.md)：内部 spec

## License

MIT. 见 [LICENSE](LICENSE)。
