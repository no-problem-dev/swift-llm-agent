import Foundation
import LLMTool

// MARK: - SubAgentEvent

/// サブエージェントの実行過程を通知するイベント
///
/// UI 表示やロギングに使用します。
/// `taskId` により並列実行中の複数サブエージェントのイベントを識別できます。
public enum SubAgentEvent: Sendable {
    /// サブエージェントが開始された
    case started(taskId: UUID, agentType: String, description: String)

    /// ツール呼び出しが発生
    case toolCall(taskId: UUID, ToolCall)

    /// ツール実行結果
    case toolResult(taskId: UUID, ToolResponse)

    /// サブエージェントが正常完了
    case completed(taskId: UUID, result: String)

    /// サブエージェントがエラーで終了
    case failed(taskId: UUID, error: any Error)
}

// MARK: - SubAgentEventHandler

/// サブエージェントイベントのハンドラー型
public typealias SubAgentEventHandler = @Sendable (SubAgentEvent) async -> Void
