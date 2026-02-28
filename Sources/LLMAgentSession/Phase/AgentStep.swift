import Foundation
import LLMTool

// MARK: - AgentStep

/// エージェント実行中のステップ
///
/// `SessionPhase.running` 中に発生する個々のステップを表します。
/// セッションが実行中の間、このステップが順次更新されます。
///
/// ## 概要
///
/// `AgentStep` は `SessionPhase.running(step:)` の associated value として使用され、
/// エージェントが現在何を行っているかを詳細に示します。
///
/// ## 使用例
///
/// ```swift
/// for await phase in session.run("調査して", model: .sonnet) {
///     switch phase {
///     case .running(let step):
///         switch step {
///         case .userMessage(let msg):
///             print("👤 \(msg)")
///         case .thinking:
///             print("🤔 思考中...")
///         case .toolCall(let call):
///             print("🔧 \(call.name)")
///         case .toolResult(let result):
///             print("📄 \(result.output)")
///         case .interrupted(let msg):
///             print("⚡ 割り込み: \(msg)")
///         }
///     case .awaitingInteraction(let request):
///         print("❓ \(request.prompt)")
///     case .completed(let result):
///         print("✅ 完了: \(result)")
///     // ...
///     }
/// }
/// ```
public enum AgentStep: Sendable, Equatable {
    /// ユーザーメッセージが送信された
    ///
    /// ユーザーの入力が会話履歴に追加されたことを示します。
    case userMessage(String)

    /// LLM が思考中
    ///
    /// LLM からの応答を処理中であることを示します。
    case thinking

    /// 思考テキストの差分（リアルタイム）
    ///
    /// Extended Thinking が有効な場合、思考テキストのチャンクが順次配信されます。
    case thinkingDelta(String)

    /// ツール呼び出しが要求された
    ///
    /// LLM がツールの実行を要求したことを示します。
    case toolCall(ToolCall)

    /// ツール実行結果
    ///
    /// ツールの実行が完了し、結果が得られたことを示します。
    case toolResult(ToolResponse)

    /// 割り込みメッセージが処理された
    ///
    /// ユーザーからの割り込みメッセージが会話履歴に追加されたことを示します。
    case interrupted(String)
}

// MARK: - CustomStringConvertible

extension AgentStep: CustomStringConvertible {
    public var description: String {
        switch self {
        case .userMessage(let msg):
            return "userMessage(\(msg.prefix(30))...)"
        case .thinking:
            return "thinking"
        case .thinkingDelta(let text):
            return "thinkingDelta(\(text.prefix(30))...)"
        case .toolCall(let call):
            return "toolCall(\(call.name))"
        case .toolResult(let result):
            return "toolResult(\(result.name))"
        case .interrupted(let msg):
            return "interrupted(\(msg.prefix(30))...)"
        }
    }
}
