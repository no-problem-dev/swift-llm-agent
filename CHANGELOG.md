# 変更履歴

このプロジェクトの全ての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [セマンティックバージョニング](https://semver.org/lang/ja/spec/v2.0.0.html) に準拠しています。

## [未リリース]

なし

## [1.28.0] - 2026-05-31

### 変更
- **LLMA2A**: 依存する swift-a2a を A2A v1.0.1 準拠（0.3.x）へ更新し、内部を全面刷新。
  - Agent Card の `supportedInterfaces` から対応バインディングを自動選択（JSON-RPC 優先・REST フォールバック）。
  - 送信結果が A2A 標準どおりタスク／メッセージ両対応に。
- **LLMA2A**（破壊的）: 公開 DTO を A2A 標準語へ整合。
  - `A2ATaskInfo.sessionId` → `contextId`、`state` を型付き `A2ATaskState`（`rejected` 含む）へ。
  - `A2AAgentProtocol.sendMessage` の戻り値を `A2ATaskInfo` から `A2ASendResult` へ、引数 `sessionId` を `contextId` へ。

### 追加
- **LLMA2A**: `A2ATaskState` / `A2AMessageInfo` / `A2ASendResult` を追加。

## [1.0.0] - 2026-02-23

### 追加
- 初回リリース
- **LLMAgent** - エージェントコアアーキテクチャ
- **LLMMCP** - Model Context Protocol 統合
- **LLMAgentSession** - セッション管理
- **LLMToolkits** - 再利用可能なツールキット

[未リリース]: https://github.com/no-problem-dev/swift-llm-agent/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/no-problem-dev/swift-llm-agent/releases/tag/v1.0.0
