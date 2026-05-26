import Foundation
import LLMClient
import LLMTool

// MARK: - TextAgentStepSequence

/// `TextAgentLoopRunner` を AsyncSequence として公開する具象実装。
internal struct TextAgentStepSequence<Client: AgentCapableClient>: AgentTextStepStream
    where Client.Model: Sendable
{
    typealias Element = AgentTextStep

    private let client: Client
    private let model: Client.Model
    let context: AgentContext
    private let runner: TextAgentLoopRunner<Client>

    init(client: Client, model: Client.Model, context: AgentContext, configuration: AgentConfiguration) {
        self.client = client
        self.model = model
        self.context = context
        self.runner = TextAgentLoopRunner(
            client: client, model: model, context: context, configuration: configuration
        )
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(runner: runner)
    }

    func currentPhase() async -> AgentExecutionPhase {
        await runner.currentPhase()
    }

    func cancel() async {
        await runner.cancel()
    }
}

// MARK: - TextAgentStepSequence.AsyncIterator

extension TextAgentStepSequence {
    struct AsyncIterator: AsyncIteratorProtocol {
        private let runner: TextAgentLoopRunner<Client>

        init(runner: TextAgentLoopRunner<Client>) {
            self.runner = runner
        }

        mutating func next() async throws -> Element? {
            try await runner.nextStep()
        }
    }
}
