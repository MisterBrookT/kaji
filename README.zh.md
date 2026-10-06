<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev_docs/assets/kaji-cat-k-ondark.png">
    <img src="dev_docs/assets/kaji-cat-k.png" height="48" alt="K" />
  </picture>aji
</h1>

**AI 编程额度，安静地留在菜单栏。**

[English](README.md)

<img src="dev_docs/assets/use-quota.png" width="560" alt="Claude Code、Codex 和 Cursor 的额度用量与重置时间" />

</div>

## 功能

- **额度：** AI 工具的用量百分比与重置时间。
- **专注 / 休息：** 可选的专注计时与休息提醒。
- **目标：** 可选的日常与长期目标，提供 CLI 供 agent 操作。

默认只开额度，不需要的功能就关掉。黑白灰，支持浅色与深色。

## 隐私

- 读取本机的工具数据与凭据，直接向服务商查询额度、续期 token。
- prompt 和目标留在本机。没有统计、Kaji 账号或 Kaji 服务器。
- 通过 GitHub 检查和下载更新，安装前由你确认。

[额度如何计算](docs/quota.md)

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

[环境要求与排查](docs/faq.md) | [CLI](docs/cli.md)

## 贡献

欢迎 issue 与 PR，见 [AGENTS.md](AGENTS.md)。

[MIT](LICENSE)。与 AI 服务商无隶属关系。
