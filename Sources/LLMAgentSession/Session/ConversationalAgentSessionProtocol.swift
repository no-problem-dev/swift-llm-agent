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
/// ## 使用例
///
/// ```swift
/// let session = ConversationalAgentSession(client: client)
///
/// let turnConfig = TurnConfiguration(
///     systemPrompt: SystemPrompt { "リサーチアシスタントです。" },
///     tools: ToolSet { WebSearchTool() },
///     interactiveTools: InteractiveToolConfiguration(
///         priorityTools: [AskUserTool()]
///     )
/// )
///
/// for try await phase in session.run(
///     input: "調査して",
///     model: .sonnet,
///     turn: turnConfig,
///     outputType: ResearchResult.self
/// ) {
///     switch phase {
///     case .running(let step):
///         print("Step: \(step)")
///     case .awaitingInteraction(let request):
///         // InteractionView を表示して respond() を呼ぶ
///     case .completed(let output):
///         print("Result: \(output)")
///     default:
///         break
///     }
/// }
/// ```
public protocol ConversationalAgentSessionProtocol<Client>: Actor {
    associatedtype Client: AgentCapableClient where Client.Model: Sendable

    // MARK: - Properties

    var status: SessionStatus { get async }
    var running: Bool { get async }
    var turnCount: Int { get async }

    // MARK: - Interrupt API

    func interrupt(_ message: String) async
    func clearInterrupts() async

    // MARK: - Session Management

    func getMessages() async -> [LLMMessage]
    func clear() async
    func cancel() async

    // MARK: - User Interaction API

    var waitingForResponse: Bool { get async }
    func respond(_ response: InteractionResponse) async

    // MARK: - Core API

    /// LLM入力を送信してエージェントループを実行
    ///
    /// - Parameters:
    ///   - input: LLM 入力
    ///   - model: 使用するモデル
    ///   - turn: このターンの設定（ツール・システムプロンプト・エージェント設定）
    ///   - outputType: 期待する出力の型
    /// - Returns: 各フェーズを返す `AsyncThrowingStream`
    nonisolated func run<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error>

    /// 一時停止/エラーからセッションを再開
    ///
    /// - Parameters:
    ///   - model: 使用するモデル
    ///   - turn: このターンの設定
    ///   - outputType: 期待する出力の型
    /// - Returns: 各フェーズを返す `AsyncThrowingStream`
    nonisolated func resume<Output: StructuredProtocol>(
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error>
}
