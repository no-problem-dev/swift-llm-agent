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
/// ## CollaborationChannel 連携
///
/// `setChannel()` で CollaborationChannel を設定すると、内部の ConversationalAgentSession に
/// チャンネルが伝播される。`mapToEvents` 内で `.completed` を検出したとき、
/// チャンネル経由で `turnCompleted` / `contentReady` を投稿する。
public actor ChatSession<Client: AgentCapableClient>: ChatSessionProtocol
    where Client.Model: Sendable
{
    // MARK: - OutputRunner

    /// 型消去された出力処理クロージャ
    public struct OutputRunner: @unchecked Sendable {
        let run: (
            ConversationalAgentSession<Client>,
            LLMInput,
            Client.Model,
            TurnConfiguration,
            CollaborationChannel?
        ) -> AsyncThrowingStream<SessionPhaseEvent, Error>

        let resume: (
            ConversationalAgentSession<Client>,
            Client.Model,
            TurnConfiguration,
            CollaborationChannel?
        ) -> AsyncThrowingStream<SessionPhaseEvent, Error>

        let runWithPrefill: (
            ConversationalAgentSession<Client>,
            [LLMMessage],
            Client.Model,
            TurnConfiguration,
            CollaborationChannel?
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

    /// CollaborationChannel（チャンネル連携用）
    private var channel_: CollaborationChannel?

    // MARK: - Initialization

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

    public func registerModel(id: String, model: Client.Model) {
        modelRegistry[id] = model
    }

    public func registerOutputType<Output: StructuredProtocol>(
        id: String,
        type: Output.Type,
        render: @Sendable @escaping (Output) -> StructuredResult
    ) {
        outputRunnerRegistry[id] = Self.makeOutputRunner(outputType: type, renderOutput: render)
    }

    // MARK: - ChatSessionProtocol: Core Operations

    public func send(_ input: LLMInput) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        guard let model = modelRegistry[currentModelId_],
              let runner = outputRunnerRegistry[currentOutputTypeId_] else {
            return AsyncThrowingStream { $0.finish(throwing: ChatSessionError.configurationMissing) }
        }
        let config = turnConfig_
        let channel = channel_
        return runner.run(session, input, model, config, channel)
    }

    public func sendWithPrefill(_ prefill: [LLMMessage]) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        guard let model = modelRegistry[currentModelId_],
              let runner = outputRunnerRegistry[currentOutputTypeId_] else {
            return AsyncThrowingStream { $0.finish(throwing: ChatSessionError.configurationMissing) }
        }
        let config = turnConfig_
        let channel = channel_
        return runner.runWithPrefill(session, prefill, model, config, channel)
    }

    public func resume() -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        guard let model = modelRegistry[currentModelId_],
              let runner = outputRunnerRegistry[currentOutputTypeId_] else {
            return AsyncThrowingStream { $0.finish(throwing: ChatSessionError.configurationMissing) }
        }
        let config = turnConfig_
        let channel = channel_
        return runner.resume(session, model, config, channel)
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

    // MARK: - ChatSessionProtocol: Channel

    public func setChannel(_ channel: CollaborationChannel) async {
        self.channel_ = channel
        await session.setChannel(channel)
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

    nonisolated public static func makeOutputRunner<Output: StructuredProtocol>(
        outputType: Output.Type,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult
    ) -> OutputRunner {
        OutputRunner(
            run: { session, input, model, turnConfig, channel in
                let typedStream = session.run(
                    input: input,
                    model: model,
                    turn: turnConfig,
                    outputType: Output.self
                )
                return Self.mapToEvents(typedStream, renderOutput: renderOutput, channel: channel)
            },
            resume: { session, model, turnConfig, channel in
                let typedStream = session.resume(
                    model: model,
                    turn: turnConfig,
                    outputType: Output.self
                )
                return Self.mapToEvents(typedStream, renderOutput: renderOutput, channel: channel)
            },
            runWithPrefill: { session, prefill, model, turnConfig, channel in
                let typedStream = session.runWithPrefill(
                    prefill: prefill,
                    model: model,
                    turn: turnConfig,
                    outputType: Output.self
                )
                return Self.mapToEvents(typedStream, renderOutput: renderOutput, channel: channel)
            }
        )
    }

    // MARK: - Private: Phase Mapping

    private static func mapToEvents<Output: StructuredProtocol>(
        _ stream: AsyncThrowingStream<SessionPhase<Output>, Error>,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult,
        channel: CollaborationChannel?
    ) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await phase in stream {
                        if Task.isCancelled { break }
                        let event = mapPhase(phase, renderOutput: renderOutput)
                        continuation.yield(event)

                        // チャネルに完了イベントを送信
                        if let channel {
                            switch event {
                            case .completed(let result):
                                await channel.post(.turnCompleted(result), from: "orchestrator")
                                await channel.post(.contentReady(
                                    ContentIntent(content: result.markdown)
                                ), from: "orchestrator")
                            default:
                                break
                            }
                        }
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
