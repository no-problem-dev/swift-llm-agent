import Foundation

/// プロバイダー非依存のチャットセッションインターフェース
///
/// `ConversationalAgentSession<Client>` のジェネリクスを隠蔽し、
/// UI 層が単一の参照で全プロバイダーのセッションを扱えるようにする。
public protocol ChatSessionProtocol: Sendable {
    /// メッセージを送信してフェーズイベントのストリームを返す
    func send(_ text: String) -> AsyncThrowingStream<SessionPhaseEvent, Error>

    /// インタラクティブモードでの回答
    func reply(_ answer: String) async

    /// 実行中に割り込みメッセージを送信
    func interrupt(_ message: String) async

    /// 一時停止/エラーから再開
    func resume() -> AsyncThrowingStream<SessionPhaseEvent, Error>

    /// 現在の実行をキャンセル
    func cancel() async

    /// 会話履歴をクリア
    func clear() async

    /// シリアライズされた会話メッセージを取得（セッション永続化用）
    func getSerializedMessages() async -> Data?
}

// MARK: - Default Implementations

extension ChatSessionProtocol {
    public func interrupt(_ message: String) async {
        // デフォルトは no-op
    }

    public func resume() -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        // デフォルトは空ストリーム
        AsyncThrowingStream { $0.finish() }
    }

    public func getSerializedMessages() async -> Data? {
        // デフォルトは nil（サポートしないセッション用）
        nil
    }
}
