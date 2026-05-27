import A2UICore
import A2UIParser
import LLMAgent
import LLMClient
import LLMTool

internal struct A2UIAgentStepSequence<Client: AgentCapableClient>: A2UIAgentStepStream
where Client.Model: Sendable {
    typealias Element = A2UIAgentStep

    private let stream: AsyncThrowingStream<A2UIAgentStep, Error>

    init(
        client: Client,
        model: Client.Model,
        initialMessages: [LLMMessage],
        tools: ToolSet,
        systemPrompt: SystemPrompt,
        agentConfiguration: AgentConfiguration,
        a2uiConfiguration: A2UIAgentConfiguration
    ) {
        self.stream = AsyncThrowingStream { continuation in
            Task {
                await Self.runLoop(
                    client: client,
                    model: model,
                    initialMessages: initialMessages,
                    tools: tools,
                    systemPrompt: systemPrompt,
                    agentConfiguration: agentConfiguration,
                    a2uiConfiguration: a2uiConfiguration,
                    continuation: continuation
                )
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncThrowingStream<A2UIAgentStep, Error>.AsyncIterator

        init(iterator: AsyncThrowingStream<A2UIAgentStep, Error>.AsyncIterator) {
            self.iterator = iterator
        }

        mutating func next() async throws -> A2UIAgentStep? {
            try await iterator.next()
        }
    }

    // MARK: - Core Loop

    private static func runLoop(
        client: Client,
        model: Client.Model,
        initialMessages: [LLMMessage],
        tools: ToolSet,
        systemPrompt: SystemPrompt,
        agentConfiguration: AgentConfiguration,
        a2uiConfiguration: A2UIAgentConfiguration,
        continuation: AsyncThrowingStream<A2UIAgentStep, Error>.Continuation
    ) async {
        var messages = initialMessages
        var retryCount = 0

        do {
            while retryCount <= a2uiConfiguration.maxParseRetries {
                let textStream = client.runAgentText(
                    messages: messages,
                    model: model,
                    tools: tools,
                    systemPrompt: systemPrompt,
                    configuration: agentConfiguration
                )

                var finalText: String?

                for try await step in textStream {
                    switch step {
                    case .thinking(let response):
                        continuation.yield(.thinking(response))
                    case .toolCall(let call):
                        continuation.yield(.toolCall(call))
                    case .toolResult(let result):
                        continuation.yield(.toolResult(result))
                    case .finalText(let text):
                        finalText = text
                    }
                }

                guard let text = finalText else {
                    continuation.finish()
                    return
                }

                let result = A2UIResponseParser.parse(text)

                switch result {
                case .success(let parts):
                    for part in parts {
                        continuation.yield(.responsePart(part))
                    }
                    continuation.finish()
                    return

                case .failure(let originalText, let errors):
                    retryCount += 1
                    if retryCount > a2uiConfiguration.maxParseRetries {
                        continuation.yield(.responsePart(A2UIResponsePart(text: originalText)))
                        continuation.finish()
                        return
                    }

                    messages.append(.assistant(originalText))
                    let retryPrompt = A2UIResponseParser.formatRetryPrompt(
                        originalText: originalText, errors: errors
                    )
                    messages.append(.user(retryPrompt))
                }
            }

            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
