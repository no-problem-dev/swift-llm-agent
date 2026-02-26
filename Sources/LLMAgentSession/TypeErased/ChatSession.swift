import Foundation
import LLMClient
import LLMTool

/// `ConversationalAgentSession<Client>` を `ChatSessionProtocol` に適合させる汎用ラッパー
///
/// ジェネリックな `SessionPhase<Output>` を型消去された `SessionPhaseEvent` にマッピングし、
/// UI 層がプロバイダーを意識せずにセッションを操作できるようにする。
///
/// ## 使用例
///
/// ```swift
/// // StructuredOutputRenderable に準拠した型の場合（convenience init）
/// let session = ChatSession(session: agentSession, model: .sonnet)
///
/// // カスタムレンダリングの場合
/// let session = ChatSession(session: agentSession, model: .sonnet) { output in
///     StructuredResult(typeName: "Custom", markdown: output.text)
/// }
/// ```
public final class ChatSession<Client: AgentCapableClient, Output: StructuredProtocol>: ChatSessionProtocol, @unchecked Sendable
    where Client.Model: Sendable
{
    private let session: ConversationalAgentSession<Client>
    private let model: Client.Model
    private let renderOutput: @Sendable (Output) -> StructuredResult

    /// カスタムレンダリングクロージャを指定して初期化
    public init(
        session: ConversationalAgentSession<Client>,
        model: Client.Model,
        renderOutput: @Sendable @escaping (Output) -> StructuredResult
    ) {
        self.session = session
        self.model = model
        self.renderOutput = renderOutput
    }

    public func send(_ text: String) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let session = self.session
        let model = self.model

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await phase in session.run(
                        input: LLMInput(text),
                        model: model,
                        outputType: Output.self
                    ) {
                        if Task.isCancelled { break }
                        continuation.yield(self.mapPhase(phase))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func reply(_ answer: String) async {
        await session.reply(answer)
    }

    public func interrupt(_ message: String) async {
        await session.interrupt(message)
    }

    public func resume() -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let session = self.session
        let model = self.model

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await phase in session.resume(
                        model: model,
                        outputType: Output.self
                    ) {
                        if Task.isCancelled { break }
                        continuation.yield(self.mapPhase(phase))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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

    // MARK: - Phase Mapping

    private func mapPhase(_ phase: SessionPhase<Output>) -> SessionPhaseEvent {
        switch phase {
        case .idle:
            .idle
        case .running(let step):
            Self.mapStep(step)
        case .awaitingUserInput(let question):
            .awaitingUserInput(question: question)
        case .paused:
            .paused
        case .completed(let output):
            .completed(result: renderOutput(output))
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
        case .askingUser(let question):
            return .askingUser(question)
        }
    }
}

// MARK: - Convenience Init for StructuredOutputRenderable

extension ChatSession where Output: StructuredOutputRenderable {
    /// `StructuredOutputRenderable` 準拠型用の convenience init
    ///
    /// 出力型の `toStructuredResult()` を自動的にレンダリングに使用します。
    public convenience init(
        session: ConversationalAgentSession<Client>,
        model: Client.Model
    ) {
        self.init(session: session, model: model, renderOutput: { $0.toStructuredResult() })
    }
}
