import Foundation
import LLMClient
import LLMTool

// MARK: - AgentExecutionPhase

/// エージェントループの実行フェーズ
///
/// 外部から実行状態を監視するための公開用列挙型です。
package enum AgentExecutionPhase: Sendable, Equatable {
    /// ツール使用フェーズ
    ///
    /// LLM がツールを呼び出し可能な状態です。
    case toolUse

    /// 最終出力フェーズ
    ///
    /// ツールを無効化し、構造化出力を要求している状態です。
    case finalOutput

    /// ループ完了
    ///
    /// エージェントループが終了した状態です。
    case completed
}

// MARK: - LoopPhase

/// エージェントループの内部フェーズ
///
/// `AgentLoopRunner` が内部的に使用するフェーズ管理用の列挙型です。
/// `LLMAgentSession` の `ConversationalAgentSession` でも共有されます。
package enum LoopPhase: Sendable, Equatable {
    /// ツール使用フェーズ
    ///
    /// LLM がツールを呼び出し可能。`responseSchema` は送信しない。
    case toolUse

    /// 最終出力フェーズ
    ///
    /// ツールを無効化し、`responseSchema` を送信して構造化出力を要求。
    /// - Parameter retryCount: デコード再試行回数
    case finalOutput(retryCount: Int)

    /// ループ完了
    case completed

    /// 公開用フェーズに変換
    package var toPublic: AgentExecutionPhase {
        switch self {
        case .toolUse:
            return .toolUse
        case .finalOutput:
            return .finalOutput
        case .completed:
            return .completed
        }
    }
}

// MARK: - AgentLoopConstants

/// エージェントループで共有される定数
///
/// `AgentLoopRunner` と `ConversationalAgentSession` の両方で
/// 使用される定数を一元管理します。
package enum AgentLoopConstants {
    /// 最終出力要求メッセージ
    ///
    /// 構造化出力（responseSchema）を要求する際に追加するユーザーメッセージ。
    package static let finalOutputRequestMessage = "Please provide your final response in the required JSON format."

    /// 最終出力デコードの最大再試行回数
    package static let maxDecodeRetries: Int = 2
}

// MARK: - PendingEvent

/// 保留中のイベント
///
/// 思考（LLM 応答）・ツール呼び出し・結果を順次返すためにバッファリングされるイベントです。
internal enum PendingEvent: Sendable {
    /// 思考イベント（LLM の生レスポンス。`usage` を含む）。
    ///
    /// ツールを呼ぶターンでも `usage` をストリームへ漏らさず届けるために用いる。
    case thinking(LLMResponse)

    /// ツール呼び出しイベント
    case toolCall(ToolCall)

    /// ツール結果イベント
    case toolResult(ToolResponse)
}
