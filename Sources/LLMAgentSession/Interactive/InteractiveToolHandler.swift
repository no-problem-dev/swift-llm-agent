import Foundation

/// インタラクティブツール実行のハンドラプロトコル
///
/// `ConversationalAgentSession` がインタラクティブツール（`InteractiveTool` 準拠）を
/// 検出した際に、UI レイヤーに処理を委譲するためのインターフェース。
///
/// アプリ側で UIAgent 等を介した実装を注入し、
/// ユーザーインタラクション → 応答 → ToolResult 変換のフローを実現する。
public protocol InteractiveToolHandler: Sendable {
    /// インタラクションリクエストを処理し、ユーザーの応答を返す
    ///
    /// - Parameter intent: ツールコール情報 + InteractionRequest
    /// - Returns: ユーザーの応答
    func handleInteraction(_ intent: InteractionIntent) async -> InteractionResponse
}
