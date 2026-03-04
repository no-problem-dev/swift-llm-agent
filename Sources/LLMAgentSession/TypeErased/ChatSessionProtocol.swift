import Foundation
import LLMClient

// MARK: - ChatSessionProtocol

/// プロバイダー非依存のチャットセッションインターフェース
///
/// `ConversationalAgentSession<Client>` のジェネリクスを隠蔽し、
/// UI 層が単一の参照で全プロバイダーのセッションを扱えるようにする。
///
/// ## CollaborationChannel 連携
///
/// `setChannel()` でチャンネルを設定し、UIAgent・Orchestrator との通信を行う。
/// インタラクション応答・承認応答はチャンネル経由で送信する。
public protocol ChatSessionProtocol: Sendable {

    // MARK: - Core Operations

    /// メッセージを送信してフェーズイベントのストリームを返す
    func send(_ input: LLMInput) async -> AsyncThrowingStream<SessionPhaseEvent, Error>

    /// プリフィルメッセージを注入してフェーズイベントのストリームを返す
    func sendWithPrefill(_ prefill: [LLMMessage]) async -> AsyncThrowingStream<SessionPhaseEvent, Error>

    /// 一時停止/エラーから再開
    func resume() async -> AsyncThrowingStream<SessionPhaseEvent, Error>

    /// 実行中に割り込みメッセージを送信
    func interrupt(_ message: String) async

    /// 現在の実行をキャンセル
    func cancel() async

    /// 会話履歴をクリア
    func clear() async

    /// シリアライズされた会話メッセージを取得（セッション永続化用）
    func getSerializedMessages() async -> Data?

    // MARK: - Channel

    /// CollaborationChannel を設定
    func setChannel(_ channel: CollaborationChannel) async

    // MARK: - Turn Configuration

    /// 現在のターン設定
    var turnConfiguration: TurnConfiguration { get async }

    /// ターン設定を更新
    func setTurnConfiguration(_ config: TurnConfiguration) async

    // MARK: - Model Selection

    /// 現在選択されているモデルの ID
    var currentModelId: String { get async }

    /// 登録されているモデル ID の一覧
    var registeredModelIds: [String] { get async }

    /// モデルを選択
    func selectModel(id: String) async

    // MARK: - Output Type Selection

    /// 現在選択されている出力型の ID
    var currentOutputTypeId: String { get async }

    /// 登録されている出力型 ID の一覧
    var registeredOutputTypeIds: [String] { get async }

    /// 出力型を選択
    func selectOutputType(id: String) async
}
