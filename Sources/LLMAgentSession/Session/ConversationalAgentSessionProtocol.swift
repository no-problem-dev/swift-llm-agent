import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - ConversationalAgentSessionProtocol

/// 会話型エージェントセッションのプロトコル
///
/// 会話履歴を保持しながらエージェントループを実行し、
/// ターンごとに設定（ツール・システムプロンプト・モデル・出力型）を変更可能にします。
///
/// ## 設計原則
///
/// セッションは**会話履歴のみ**を保持し、それ以外の設定は
/// `TurnConfiguration` として `run()` / `resume()` の呼び出し時に渡されます。
///
/// ## CollaborationChannel 連携
///
/// `setChannel()` でチャンネルを設定すると、InteractiveTool / ToolApproval の
/// 処理がチャンネル経由に切り替わる。
public protocol ConversationalAgentSessionProtocol<Client>: Actor {
    associatedtype Client: AgentCapableClient where Client.Model: Sendable

    // MARK: - Properties

    var status: SessionStatus { get async }
    var running: Bool { get async }
    var turnCount: Int { get async }

    // MARK: - Channel

    /// コラボレーションチャンネルを設定
    func setChannel(_ channel: CollaborationChannel) async

    // MARK: - Interrupt API

    func interrupt(_ message: String) async
    func clearInterrupts() async

    // MARK: - Session Management

    func getMessages() async -> [LLMMessage]
    func clear() async
    func cancel() async

    // MARK: - Core API

    /// LLM入力を送信してエージェントループを実行
    nonisolated func run<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error>

    /// 一時停止/エラーからセッションを再開
    nonisolated func resume<Output: StructuredProtocol>(
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error>

    /// プリフィルメッセージを注入してエージェントループを実行
    nonisolated func runWithPrefill<Output: StructuredProtocol>(
        prefill: [LLMMessage],
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error>
}
