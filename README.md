[English](README_EN.md) | 日本語

> [!WARNING]
> **このパッケージは廃止されました（2026-07-19）。** 本リポジトリはアーカイブされ、今後保守されません。
>
> 後継パッケージ:
> - MCP ツール実行 / Web フェッチ → [swift-llm-mcp](https://github.com/no-problem-dev/swift-llm-mcp)（LLMMCP / WebFetchKit）
> - エージェントループ / ランタイム → [swift-agent-runtime](https://github.com/no-problem-dev/swift-agent-runtime)
> - エージェントスキル → [swift-agent-skills](https://github.com/no-problem-dev/swift-agent-skills)
> - A2A プロトコル → [swift-a2a](https://github.com/no-problem-dev/swift-a2a)
> - LLM クライアント / ツール定義 → [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client)
>
> デバイストゥールキット（LLMiOSToolkits / LLMmacOSToolkits）と Interactive Payload 型システムに後継はありません。必要な場合は本リポジトリの git 履歴を参照してください。

# LLMAgent

LLM エージェントアーキテクチャ Swift パッケージ

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 特徴

- **エージェントアーキテクチャ** - ツール実行ループを備えた自律的な LLM エージェント
- **MCP 統合** - Model Context Protocol によるツールサーバー連携
- **セッション管理** - 会話状態の永続化・復元
- **ツールキット** - 再利用可能なツールセットの提供

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-agent.git", .upToNextMajor(from: "1.0.0"))
]
```

### モジュール構成

用途に応じて必要なモジュールのみをインポートできます：

| モジュール | 用途 |
|-----------|------|
| `LLMAgent` | エージェントコア（実行ループ・ツール管理） |
| `LLMMCP` | Model Context Protocol 統合 |
| `LLMAgentSession` | セッション管理（状態永続化・復元） |
| `LLMToolkits` | 再利用可能なツールキット |

## クイックスタート

### エージェントの作成

```swift
import LLMAgent

let agent = Agent(
    provider: provider,  // any LLMProvider
    tools: toolSet       // ToolSet
)

// エージェント実行（ツール呼び出しを自動処理）
let response = try await agent.run(
    messages: [.user("プロジェクトの README を作成して")]
)
```

### MCP サーバーとの連携

```swift
import LLMMCP

let mcpClient = MCPToolProvider(
    serverCommand: "npx",
    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
)

let tools = try await mcpClient.tools()
```

### セッション管理

```swift
import LLMAgentSession

let session = AgentSession(agent: agent)

// セッションの保存・復元
try await session.save(to: sessionURL)
let restored = try await AgentSession.load(from: sessionURL, agent: agent)
```

## ドキュメント

詳細なガイドと API リファレンスは DocC ドキュメントを参照してください。

| ガイド | 内容 |
|-------|------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-agent/documentation/llmagent/) | 全パブリック API |

## 要件

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## 依存関係

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.1.0) - LLM クライアント抽象化
- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (>= 0.10.0) - Model Context Protocol SDK

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

## リンク

- [完全なドキュメント](https://no-problem-dev.github.io/swift-llm-agent/documentation/llmagent/)
- [Issue報告](https://github.com/no-problem-dev/swift-llm-agent/issues)
- [ディスカッション](https://github.com/no-problem-dev/swift-llm-agent/discussions)
- [リリースプロセス](RELEASE_PROCESS.md)
