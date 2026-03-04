import Foundation
import LLMClient

// MARK: - ChannelMessage

/// チャンネル上の 1 メッセージ
///
/// 全参加者（user, orchestrator, uiAgent）が同じ型でメッセージを投稿する。
/// `sender` で発信者を識別し、`content` で共通の語彙を使って通信する。
public struct ChannelMessage: Sendable, Identifiable {
    public let id: String
    public let sender: String
    public let content: ChannelContent
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        sender: String,
        content: ChannelContent,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - ChannelContent

/// メッセージ内容（全参加者共通の語彙）
///
/// `OrchestratorMessage` と `UIAgentMessage` を統合した単一の enum。
/// 誰でもどのケースでも投稿可能で、他の subscriber が反応する。
public enum ChannelContent: Sendable {
    // ユーザー発
    /// ユーザー入力
    case userInput(LLMInput)
    /// ユーザーアクション（フォローアップ、キャンセル等）
    case userAction(UserAction)

    // Orchestrator 発
    /// ループ中のステップイベント
    case step(AgentStep)
    /// UI化すべきコンテンツ
    case contentReady(ContentIntent)
    /// ターン正常完了
    case turnCompleted(StructuredResult)
    /// ターンエラー
    case turnFailed(String)

    // ブロッキングリクエスト / 応答
    /// ユーザー入力要求（InteractiveTool 起因）
    case requestInteraction(InteractionIntent)
    /// ツール承認要求（ToolExecutionPolicy 起因）
    case requestAuthorization(ToolApprovalRequest)
    /// インタラクション応答
    case interactionResponse(InteractionResponse, forRequestId: String)
    /// ツール承認応答
    case authorizationResponse(ToolApprovalResponse, forRequestId: String)

    // ライフサイクル
    /// セッションキャンセル
    case sessionCancelled
}

// MARK: - ContentIntent

/// 緩やかな UI 指示
///
/// Orchestrator が「このテキストを UI 化してほしい」と UIAgent に伝える。
/// UIAgent は UIGenerationRunner 等を使ってブロック変換を行う。
public struct ContentIntent: Sendable, Identifiable {
    public let id: String
    public let content: String
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - InteractionIntent

/// インタラクション要求（InteractiveTool の makeInteractionRequest 結果をラップ）
public struct InteractionIntent: Sendable, Identifiable {
    public let id: String
    public let toolCallId: String
    public let toolName: String
    public let request: InteractionRequest

    public init(
        id: String = UUID().uuidString,
        toolCallId: String,
        toolName: String,
        request: InteractionRequest
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.request = request
    }
}

// MARK: - UserAction

/// ユーザーの直接アクション
public struct UserAction: Sendable {
    public enum ActionType: Sendable {
        case followUp
        case cancel
    }

    public let type: ActionType
    public let message: String

    public init(type: ActionType, message: String) {
        self.type = type
        self.message = message
    }
}
