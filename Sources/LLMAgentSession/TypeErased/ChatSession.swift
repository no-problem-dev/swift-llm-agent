import Foundation
import LLMClient
import LLMTool

// MARK: - ChatSession

/// プロバイダー非依存の型消去チャットセッション
///
/// `ConversationalAgentSession<Client>` をラップし、`ChatSessionProtocol` に適合させる。
/// ジェネリックな `SessionPhase<Output>` を型消去された `SessionPhaseEvent` にマッピングし、
/// UI 層がプロバイダーを意識せずにセッションを操作できるようにする。
///
/// ## 設計
///
/// - **Actor**: スレッドセーフなミュータブル状態管理
/// - **OutputRunner パターン**: `Output` ジェネリクスをクロージャでキャプチャし型消去
/// - **レジストリパターン**: モデル・出力型を ID ベースで登録・選択
///
/// ## 使用例
///
/// ```swift
/// let agentSession = ConversationalAgentSession(client: anthropicClient)
///
/// let chatSession = ChatSession(
///     session: agentSession,
///     initialModelId: "Sonnet",
///     initialOutputTypeId: "research",
///     initialTurnConfiguration: turnConfig
/// )
///
/// // モデルを登録
/// await chatSession.registerModel(id: "Sonnet", model: .sonnet)
/// await chatSession.registerModel(id: "Haiku", model: .haiku)
///
/// // 出力型を登録
/// await chatSession.registerOutputType(id: "research", type: ResearchResult.self) {
///     $0.toStructuredResult()
/// }
///
/// // 使用
/// for try await event in await chatSession.send("調査して") { ... }
///
/// // ターン間でモデルを変更
/// await chatSession.selectModel(id: "Haiku")
/// for try await event in await chatSession.send("要約して") { ... }
/// ```
public actor ChatSession<Client: AgentCapableClient>: ChatSessionProtocol
    where Client.Model: Sendable
{
    // MARK: - OutputRunner

    /// 型消去された出力処理クロージャ
    ///
    /// `Output` ジェネリクスを `registerOutputType` 時にクロージャ内にキャプチャし、
    /// `send()` / `resume()` 時に型消去された `SessionPhaseEvent` ストリームを返す。
    ///
    /// `makeOutputRunner` ファクトリメソッドで生成し、init 時または `registerOutputType` で登録する。
    public struct OutputRunner: @unchecked Sendable {
        let run: (
            ConversationalAgentSession<Client>,
            LLMInput,
            Client.Model,
            TurnConfiguration
        ) -> AsyncThrowingStream<SessionPhaseEvent, Error>

        let resume: (
            ConversationalAgentSession<Client>,
            Client.Model,
            TurnConfiguration
        ) -> AsyncThrowingStream<SessionPhaseEvent, Error>
    }

    // MARK: - Properties

    private let session: ConversationalAgentSession<Client>

    /// 現在のモデル ID
    private var currentModelId_: String

    /// 現在の出力型 ID
    private var currentOutputTypeId_: String

    /// 現在のターン設定
    private var turnConfig_: TurnConfiguration

    /// モデルレジストリ（ID → Model）
    private var modelRegistry: [String: Client.Model]

    /// 出力型レジストリ（ID → OutputRunner）
    private var outputRunnerRegistry: [String: OutputRunner]

    // MARK: - Initialization

    /// ChatSession を初期化
    ///
    /// - Parameters:
    ///   - session: 会話セッション
    ///   - initialModelId: 初期モデル ID
    ///   - initialOutputTypeId: 初期出力型 ID
    ///   - initialTurnConfiguration: 初期ターン設定
    ///   - models: 初期モデルレジストリ（ID → Model）
    ///   - outputRunners: 初期出力型レジストリ（ID → OutputRunner）
    public init(
        session: ConversationalAgentSession<Client>,
        initialModelId: String,
        initialOutputTypeId: String,
        initialTurnConfiguration: TurnConfiguration,
        models: [String: Client.Model] = [:],
        outputRunners: [String: OutputRunner] = [:]
    ) {
        self.session = session
        self.currentModelId_ = initialModelId
        self.currentOutputTypeId_ = initialOutputTypeId
        self.turnConfig_ = initialTurnConfiguration
        self.modelRegistry = models
        self.outputRunnerRegistry = outputRunners
    }

    // MARK: - Registration

    /// モデルを登録
    ///
    /// - Parameters:
    ///   - id: モデル ID（表示名など）
    ///   - model: モデル値
    public func registerModel(id: String, model: Client.Model) {
        modelRegistry[id] = model
    }

    /// 出力型を登録
    ///
    /// - Parameters:
    ///   - id: 出力型 ID
    ///   - type: 出力の型
    ///   - render: 出力を `StructuredResult` に変換するクロージャ
    public func registerOutputType<Output: StructuredProtocol>(
        id: String,
        type: Output.Type,
        render: @Sendable @escaping (Output) -> StructuredResult
    ) {
        outputRunnerRegistry[id] = Self.makeOutputRunner(outputType: type, renderOutput: render)
    }

    // MARK: - ChatSessionProtocol: Core Operations

    public func send(_ text: String) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        guard let model = modelRegistry[currentModelId_],
              let runner = outputRunnerRegistry[currentOutputTypeId_] else {
            return AsyncThrowingStream { $0.finish(throwing: ChatSessionError.configurationMissing) }
        }
        let config = turnConfig_
        return runner.run(session, LLMInput(text), model, config)
    }

    public func resume() -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        guard let model = modelRegistry[currentModelId_],
              let runner = outputRunnerRegistry[currentOutputTypeId_] else {
            return AsyncThrowingStream { $0.finish(throwing: ChatSessionError.configurationMissing) }
        }
        let config = turnConfig_
        return runner.resume(session, model, config)
    }

    public func respond(_ response: InteractionResponse) async {
        await session.respond(response)
    }

    public func interrupt(_ message: String) async {
        await session.interrupt(message)
    }

    public func cancel() async {
        await session.cancel()
    }

    public func clear() async {
        await session.clear()
    }

    public func getSerializedMessages() async -> Data? {
        let messages = await session.getMessages()
        return try? JSONEncoder().encode(messages)
    }

    // MARK: - ChatSessionProtocol: Turn Configuration

    public var turnConfiguration: TurnConfiguration {
        turnConfig_
    }

    public func setTurnConfiguration(_ config: TurnConfiguration) {
        turnConfig_ = config
    }

    // MARK: - ChatSessionProtocol: Model Selection

    public var currentModelId: String {
        currentModelId_
    }

    public var registeredModelIds: [String] {
        Array(modelRegistry.keys)
    }

    public func selectModel(id: String) {
        guard modelRegistry[id] != nil else { return }
        currentModelId_ = id
    }

    // MARK: - ChatSessionProtocol: Output Type Selection

    public var currentOutputTypeId: String {
        currentOutputTypeId_
    }

    public var registeredOutputTypeIds: [String] {
        Array(outputRunnerRegistry.keys)
    }

    public func selectOutputType(id: String) {
        guard outputRunnerRegistry[id] != nil else { return }
        currentOutputTypeId_ = id
    }

    // MARK: - OutputRunner Factory

    /// OutputRunner を作成する型消去ファクトリメソッド
    ///
    /// Actor 隔離に依存しないため `nonisolated` かつ `static`。
    /// init 時のレジストリ構築や、動的な `registerOutputType` の両方で使用する。
    nonisolated public static func makeOutputRunner<Output: StructuredProtocol>(
        outputType: Output.Type,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult
    ) -> OutputRunner {
        OutputRunner(
            run: { session, input, model, turnConfig in
                let typedStream = session.run(
                    input: input,
                    model: model,
                    turn: turnConfig,
                    outputType: Output.self
                )
                return Self.mapToEvents(typedStream, renderOutput: renderOutput)
            },
            resume: { session, model, turnConfig in
                let typedStream = session.resume(
                    model: model,
                    turn: turnConfig,
                    outputType: Output.self
                )
                return Self.mapToEvents(typedStream, renderOutput: renderOutput)
            }
        )
    }

    // MARK: - Private: Phase Mapping

    private static func mapToEvents<Output: StructuredProtocol>(
        _ stream: AsyncThrowingStream<SessionPhase<Output>, Error>,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult
    ) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await phase in stream {
                        if Task.isCancelled { break }
                        continuation.yield(mapPhase(phase, renderOutput: renderOutput))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func mapPhase<Output: StructuredProtocol>(
        _ phase: SessionPhase<Output>,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult
    ) -> SessionPhaseEvent {
        switch phase {
        case .idle:
            .idle
        case .running(let step):
            mapStep(step)
        case .awaitingInteraction(let request):
            .awaitingInteraction(request: request)
        case .paused:
            .paused
        case .completed(let output):
            .completed(result: renderOutput(output))
        case .completedText(let text):
            .completed(result: .plainText(text))
        case .failed(let error):
            .failed(error: error)
        }
    }

    private static func mapStep(_ step: AgentStep) -> SessionPhaseEvent {
        switch step {
        case .userMessage:
            return .idle
        case .thinking:
            return .thinking
        case .thinkingDelta(let text):
            return .thinkingDelta(text)
        case .toolCall(let call):
            let args = String(data: call.arguments, encoding: .utf8) ?? "{}"
            return .toolCall(name: call.name, arguments: args)
        case .toolResult(let result):
            return .toolResult(name: result.name, output: result.output, isError: result.isError)
        case .interrupted(let msg):
            return .interrupted(msg)
        }
    }
}

// MARK: - Convenience

extension ChatSession {
    /// `StructuredOutputRenderable` 準拠型を登録する convenience メソッド
    public func registerOutputType<Output: StructuredProtocol & StructuredOutputRenderable>(
        id: String,
        type: Output.Type
    ) {
        registerOutputType(id: id, type: type) { $0.toStructuredResult() }
    }

    /// `StructuredOutputRenderable` 準拠型の OutputRunner を作成する convenience ファクトリ
    nonisolated public static func makeOutputRunner<Output: StructuredProtocol & StructuredOutputRenderable>(
        outputType: Output.Type
    ) -> OutputRunner {
        makeOutputRunner(outputType: outputType, renderOutput: { $0.toStructuredResult() })
    }
}

// MARK: - ChatSessionError

/// ChatSession 固有のエラー
public enum ChatSessionError: Error, LocalizedError, Sendable {
    /// モデルまたは出力型が登録されていない
    case configurationMissing

    public var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Model or output type not registered. Call registerModel/registerOutputType first."
        }
    }
}
