import Foundation
import LLMClient

// MARK: - UIAgentEvent

/// UIAgent → SessionAgent (MainActor) へのイベント
///
/// UIAgent が Channel からのメッセージを処理し、
/// UI 層が消費するイベントに変換して配信する。
public enum UIAgentEvent: Sendable {
    /// ユーザー入力を受信（UI に表示するため）
    case inputReceived(LLMInput)

    /// Orchestrator にタスク実行を要求
    case orchestrationRequested(LLMInput)

    /// 初期 UI ブロック（ユーザー入力時に即座に emit）
    case initialBlockEmitted(UIBlockReference)

    /// エージェントステップのパススルー
    case step(AgentStep)

    /// Generative UI 生成開始（fallback 用の rawText を含む）
    case generationStarted(rawText: String)

    /// UIBlock が生成された
    case blockGenerated(UIBlockReference)

    /// Generative UI 生成完了
    case generationCompleted

    /// Generative UI 生成失敗
    case generationFailed(String)

    /// 画像プレースホルダー挿入
    case imagePlaceholderInserted(UIBlockReference, afterBlockId: String)

    /// 画像生成完了（mediaId を注入）
    case imageGenerated(blockId: String, mediaId: String)

    /// インタラクション要求（UI にシート表示を要求）
    case interactionRequested(InteractionIntent)

    /// ツール承認要求（UI に承認ダイアログを要求）
    case authorizationRequested(ToolApprovalRequest)

    /// ターン正常完了
    case turnCompleted(StructuredResult)

    /// ターンエラー
    case turnFailed(String)

    /// セッションキャンセル
    case sessionCancelled
}

// MARK: - UIBlockReference

/// UIBlock の軽量参照（LLMAgentSession は LLMAgentInteraction に依存しないため）
///
/// SessionAgent 側で UIBlock に変換する。
public struct UIBlockReference: Sendable {
    public let id: String
    public let type: String
    public let content: String
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        type: String,
        content: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.metadata = metadata
    }
}
