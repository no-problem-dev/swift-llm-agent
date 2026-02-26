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

    /// エージェントがユーザーに質問中
    case askingUser(String)

    /// ユーザー入力待ち
    case awaitingUserInput(question: String)

    /// 一時停止
    case paused

    /// 完了
    case completed(result: StructuredResult)

    /// 失敗
    case failed(error: String)
}
