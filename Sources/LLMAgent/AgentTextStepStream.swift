import Foundation
import LLMClient
import LLMTool

// MARK: - AgentTextStep

/// テキスト出力を最終形とするエージェントループの 1 ステップ。
///
/// `AgentLoopStep<Output>` と異なり、構造化された `Output: StructuredProtocol`
/// を要求しない。LLM の応答テキストをそのまま `.finalText(String)` として返すため、
/// A2UI のように「テキスト応答中の JSON ブロックを後段でパースする」ユースケースや、
/// 単純なチャット応答を扱うのに適している。
public enum AgentTextStep: Sendable {
    /// LLM がテキストを生成中（途中段階のレスポンス）
    case thinking(LLMResponse)

    /// LLM がツール呼び出しを要求
    case toolCall(ToolCall)

    /// ツール実行結果
    case toolResult(ToolResponse)

    /// ループ完了。`text` は LLM の最終テキスト応答（ツール呼び出しが含まれていないターン）。
    case finalText(String)
}

// MARK: - AgentTextStepStream

/// 構造化出力を持たないエージェントループの AsyncSequence。
///
/// 終了条件:
/// - LLM の応答にツール呼び出しが含まれなくなった時 → `.finalText(text)` を発行して完了
/// - `maxSteps` 到達 → `AgentError.maxStepsExceeded` を throw
///
/// ## 使用例
///
/// ```swift
/// let stream = client.runAgentText(
///     messages: messages,
///     model: .gpt5Mini,
///     tools: tools,
///     systemPrompt: prompt
/// )
/// for try await step in stream {
///     switch step {
///     case .thinking, .toolCall, .toolResult:
///         break
///     case .finalText(let text):
///         // text は LLM の生応答。Markdown コードブロック等を任意に後処理。
///         break
///     }
/// }
/// ```
public protocol AgentTextStepStream: AsyncSequence, Sendable
where Element == AgentTextStep {}
