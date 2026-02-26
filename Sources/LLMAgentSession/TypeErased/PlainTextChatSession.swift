import Foundation
import LLMClient
import LLMTool

/// `PlainTextAgentSession<Client>` を `ChatSessionProtocol` に適合させるラッパー
///
/// `ChatSession` と同パターンで、`PlainTextSessionPhase` を
/// 型消去された `SessionPhaseEvent` にマッピングする。
///
/// 構造化出力を使用しないセッション（ローカル LLM 等）で使用する。
public final class PlainTextChatSession<Client: AgentCapableClient>: ChatSessionProtocol, @unchecked Sendable
    where Client.Model: Sendable
{
    private let session: PlainTextAgentSession<Client>
    private let model: Client.Model

    public init(session: PlainTextAgentSession<Client>, model: Client.Model) {
        self.session = session
        self.model = model
    }

    public func send(_ text: String) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let session = self.session
        let model = self.model

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await phase in session.run(
                        input: LLMInput(text),
                        model: model
                    ) {
                        if Task.isCancelled { break }
                        continuation.yield(Self.mapPhase(phase))
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
                    for try await phase in session.resume(model: model) {
                        if Task.isCancelled { break }
                        continuation.yield(Self.mapPhase(phase))
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

    private static func mapPhase(_ phase: PlainTextSessionPhase) -> SessionPhaseEvent {
        switch phase {
        case .idle:
            .idle
        case .running(let step):
            mapStep(step)
        case .awaitingUserInput(let question):
            .awaitingUserInput(question: question)
        case .paused:
            .paused
        case .completed(let text):
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
        case .askingUser(let question):
            return .askingUser(question)
        }
    }
}
