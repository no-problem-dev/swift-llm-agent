import Foundation

/// プロバイダー非依存のセッションフェーズイベント
///
/// `ConversationalAgentSession<Client>` の `SessionPhase<Output>` を
/// 型消去し、UI 層が単一の型で全プロバイダーを扱えるようにする。
public enum SessionPhaseEvent: Sendable {
    /// アイドル状態
    case idle

    /// LLM が思考中
    case thinking

    /// 思考テキストの差分（リアルタイム）
    case thinkingDelta(String)

    /// ツール呼び出し
    case toolCall(name: String, arguments: String)

    /// ツール実行結果
    case toolResult(name: String, output: String, isError: Bool)

    /// テキスト生成のストリーミング差分
    case textDelta(String)

    /// 割り込みメッセージ
    case interrupted(String)

    /// インタラクション待ち（Layer 1: InteractiveTool 起因）
    ///
    /// `ask_user` を含む全てのインタラクティブツールがこのイベントを使用する。
    case awaitingInteraction(request: InteractionRequest)

    /// ツール実行承認待ち（ToolExecutionPolicy 起因）
    ///
    /// ポリシーがユーザー承認を要求した場合に使用する。
    case awaitingAuthorization(request: ToolApprovalRequest)

    /// 一時停止
    case paused

    /// 完了
    case completed(result: StructuredResult)

    /// ディレクティブ付き完了（Layer 2: DirectiveGenerator 起因）
    ///
    /// セッション完了後に DirectiveGenerator が次のインタラクション提案を生成した場合に使用する。
    case directive(result: StructuredResult, request: InteractionRequest)

    /// 失敗
    case failed(error: String)
}
