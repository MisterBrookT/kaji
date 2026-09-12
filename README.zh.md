<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**值得一直留在菜单栏的 AI coding 工具。**

一眼看到还剩多少额度，其余功能想要再开。

[English](README.md)

<a href="https://github.com/MisterBrookT/kaji/stargazers"><img src="https://img.shields.io/github/stars/MisterBrookT/kaji?style=flat&label=stars&labelColor=1A1A1A&color=8A8A8A" alt="GitHub stars"></a>
<img src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-8A8A8A?labelColor=1A1A1A" alt="macOS 13+, Apple Silicon">
<a href="LICENSE"><img src="https://img.shields.io/github/license/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="MIT license"></a>
<img src="https://img.shields.io/github/v/release/MisterBrookT/kaji?color=8A8A8A&labelColor=1A1A1A" alt="Latest release">

<img src="dev_docs/assets/use-quota.png" width="560" alt="Kaji quota 面板：Claude Code、Codex、Cursor 各自的两个用量窗口、百分比与重置时间" />

</div>

## 是什么

Claude Code 和 Codex 都按滚动窗口计量。Kaji 把答案放进菜单栏：用了多少，什么时候重置。

每个 provider 显示它的两个窗口——短的会话窗口和长的那个——各自带百分比与重置时间。不用打开任何东西，也不用问。

默认只开 Quota。专注计时、系统负载、目标都是可选模块，想要再开。`Kaji` 来自日语 `舵 / かじ`。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

需要 macOS 13+（Apple Silicon），以及 `git`、`swift`、`python3`。安装脚本会从最新 release tag 本机构建并装到 `/Applications`。

没有预编译下载：Kaji 还没有 Developer ID 签名，浏览器下载的未签名 `.app.zip` 会被 Gatekeeper 拦下，本机构建反而更诚实。已经 clone 的话执行 `./scripts/build-local.sh`。

出问题或想卸载：[常见问题与排查](docs/faq.md)。

## 模块

| 模块 | 默认 | 能力 |
| --- | --- | --- |
| **Quota** | 开 | 每个 provider、每个窗口的用量与重置时间 |
| **Work / Break** | 关 | 专注计时、菜单栏倒计时、休息遮罩 |
| **System** | 关 | CPU / 内存、磁盘分类、顶部进程 |
| **Goals** | 关 | Today / Week / Vision、标签、说明、`kaji` CLI |

关掉一个模块不只是隐藏页面，同时会停掉它的定时器与轮询。只有一套主题：黑白灰，浅色与深色。

<details>
<summary>专注计时与目标</summary>

<br>

不用打开任何界面就能读到的倒计时，以及真的会打断你的休息。

<img src="dev_docs/assets/use-work.png" width="480" alt="Work 面板：剩余 07:57，45m 专注 / 2m 休息" />

Today / Week / Vision 三层目标，并提供 `kaji` CLI，让 agent 帮你增删与完成。

<img src="dev_docs/assets/use-goals.png" width="480" alt="Goals 面板：按标签分组的今日目标" />

</details>

## 隐私

Kaji 读取 AI 工具本来就写在你 Mac 上的文件；对于只在服务端公布额度的 provider，用你本机已有的凭据调用它自己的用量接口。

- **本地读取：** `~/.claude/projects/**/*.jsonl`、`~/.codex/sessions/**/rollout-*.jsonl`，以及必要时的本地凭据。
- **离开本机的请求：** 带你自己 token 的 `api.anthropic.com` 或 `api2.cursor.sh` 用量请求，以及向 `api.github.com` 检查新版本。只针对你启用的 provider。
- **没有统计、没有账号、没有我们的服务器。** prompt、用量、目标都不会被上传。CLI 只通过 `127.0.0.1` 与 App 通信。

每个数字怎么算：[quota 原理](docs/quota.md)。

## 文档

- [quota 原理](docs/quota.md) · [常见问题](docs/faq.md) · [CLI 参考](docs/cli.md)
- [产品原则](docs/product-principles.md) · [模块架构](docs/module-architecture.md) · [设计语言](docs/design-language.md)
- [AGENTS.md](AGENTS.md)：贡献者 / agent 笔记

## 贡献

欢迎 issue 与 PR。提 PR 前请跑 `swift test`；布局不变量与 UI 测试分层见 [AGENTS.md](AGENTS.md)。

## License

MIT，见 [LICENSE](LICENSE)。

与 Anthropic、OpenAI、Anysphere 及其他 provider 无隶属关系；相关名称与商标归各自所有者。
