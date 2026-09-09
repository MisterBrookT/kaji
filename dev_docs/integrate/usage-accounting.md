# 用量读取契约

`Resources/quota.py` 是 Kaji 唯一的用量数据源。它读取各 harness 的本地会话文件与
账号接口，输出 `tokens_today` 与 `limits`。这份文档记录**必须保持不变的计数规则**，
因为每一条都对应一个已经出现过的错误读数。

## 时间边界

`TODAY_START` 是**本地午夜**，不是 UTC 午夜。

UTC 边界在 UTC+8 会让"今天"从本地 08:00 才开始，整个上午的用量被静默丢弃；在
UTC-5 又会把昨晚算进今天。所有 harness 共用这一个边界。

## Claude Code

会话记录在 `~/.claude/projects/**/*.jsonl`，每行一条 `message.usage`。

| 规则 | 原因 |
| --- | --- |
| tokens = `input + output + cache_creation + cache_read` | cache 读取约占真实流量 99%；只算 input+output 等于几乎什么都没统计 |
| 按 `(message.id, requestId)` 全局去重 | resume / 分支 / compact 会把旧轮次**重写**进新文件，裸求和会把同一次 API 调用算多遍 |
| 跳过 `model == "<synthetic>"` | 本地错误占位，不计费 |
| 包含 `subagents/` 下的文件 | sidechain 轮次是真实计费用量 |
| 扫描 `CLAUDE_CONFIG_DIR`（逗号分隔）、`~/.claude`、`~/.config/claude` | 迁移过 config 目录的用户否则永远读到 0 |

`context`（当前上下文占用）在去重**之前**读取：重复记录描述的仍是真实上下文大小。

计数口径与社区工具 `ccusage` 对齐，便于交叉核对。

## Codex

会话记录在 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 的 `token_count` 事件。

- 事件里的 `total_token_usage` 是**会话累计**，`last_token_usage` 是本轮增量。
  `tokens_today` 必须累加**时间戳落在今天**的 `last_token_usage`。取最后一条累计值
  会把一个跨周会话的全部历史算进它最后活跃的那一天。
- 跳过累计值与上一条完全相同的事件：TUI 重绘会重复发送同一个 `token_count`。
- 额度百分比按**窗口时长**映射，绝不按 `primary` / `secondary` 槽位名：

  ```
  window_minutes <= 1440  ->  five_hour
  window_minutes >  1440  ->  seven_day
  ```

  Codex 把 `primary` 用作"当前生效的窗口"。只有周额度的套餐会给出
  `primary.window_minutes == 10080` 且 `secondary == null`——信任槽位名就会把
  7 天数字画到 5 小时环上。

- 实时读数走 `codex -s read-only -a never app-server` 的
  `account/rateLimits/read`。审批策略枚举里**没有** `untrusted`（0.153.x 只接受
  `on-request` / `never`），传错值会让 CLI 在响应任何 JSON-RPC 之前退出，于是所有读数
  静默退化成过期的会话文件。

## 测试

`Tests/quota/test_quota.py`（纯标准库、临时目录 fixture、无网络、不读用户数据）覆盖
上面每一条规则，由 CI 在 `swift test` 之前运行。改动计数逻辑必须保持它为绿。
