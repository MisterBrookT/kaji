# 四语本地化规则

Kaji 固定支持四种界面语言：

| 语言 | 存储值 | 设置标签 |
| --- | --- | --- |
| English | `en` | `EN` |
| 简体中文 | `zh` | `中文` |
| Português (Brasil) | `pt-BR` | `PT-BR` |
| Español | `es` | `ES` |

全新安装默认 English，不跟随系统语言。已有 `language` 选择必须原样保留。

新增用户可见文案时：

1. 在 `KajiCore/LanguageLocalization.swift` 增加类型安全的 `L10n.K`。
2. 同一变更提供 `en / zh / ptBR / es` 四个自然、紧凑的翻译。
3. 不直接在 SwiftUI view 中写可翻译字符串。
4. 产品名、供应商名、模型名、命令、路径、URL 和 `5h` / `7d` 等技术标记保持原文。
5. 运行 `swift test`；完整性测试会拒绝任一语言空字符串。
