import Foundation

/// プロバイダー非依存のセッションフェーズイベント
///
/// `ConversationalAgentSession<Client>` の `SessionPhase<Output>` を
/// 型消去し、UI 層が単一の型で全プロバイダーを扱えるようにする。
///
/// インタラクション・承認・ディレクティブは UIAgentEvent 経由で配信されるため、
/// このイベントには含まれない。
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

    /// 割り込みメッセージ
    case interrupted(String)

    /// 一時停止
    case paused

    /// キャンセル済み
    case cancelled

    /// 完了
    case completed(result: StructuredResult)

    /// ターン終了（skipFinalOutput 時: .completed を経由せずループが終了した場合）
    case turnEnded

    /// 失敗
    case failed(error: SessionError)
}
