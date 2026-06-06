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
        do {
            // Phase 1: Full agent loop with tools
            let textStream = client.runAgentText(
                messages: initialMessages,
                model: model,
                tools: tools,
                systemPrompt: systemPrompt,
                configuration: agentConfiguration
            )

            var finalText: String?
            var messages: [LLMMessage] = initialMessages
            for try await step in textStream {
                switch step {
                case .thinking(let response):
                    continuation.yield(.thinking(response))
                case .toolCall(let call):
                    continuation.yield(.toolCall(call))
                case .toolResult(let result):
                    continuation.yield(.toolResult(result))
                case .finalText(let text, let finalMessages):
                    finalText = text
                    messages = finalMessages
                }
            }

            guard let text = finalText else {
                continuation.yield(.turnCompleted(messages: messages))
                continuation.finish()
                return
            }

            // Phase 2: Parse and retry if needed
            let parsed = try await parseWithRetry(
                text: text,
                messages: &messages,
                client: client,
                model: model,
                systemPrompt: systemPrompt,
                a2uiConfiguration: a2uiConfiguration,
                continuation: continuation
            )

            for part in parsed {
                continuation.yield(.responsePart(part))
            }
            continuation.yield(.turnCompleted(messages: messages))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Parse A2UI blocks from text. On failure, retry with a direct LLM call (no tools).
    private static func parseWithRetry(
        text: String,
        messages: inout [LLMMessage],
        client: Client,
        model: Client.Model,
        systemPrompt: SystemPrompt,
        a2uiConfiguration: A2UIAgentConfiguration,
        continuation: AsyncThrowingStream<A2UIAgentStep, Error>.Continuation
    ) async throws -> [A2UIResponsePart] {
        var currentText = text
        var lastErrors: [A2UIParseError] = []

        for attempt in 0...a2uiConfiguration.maxParseRetries {
            continuation.yield(.decodeEvent(.attempt(index: attempt, text: currentText)))
            let result = A2UIResponseParser.parse(currentText)

            switch result {
            case .success(let parts):
                continuation.yield(.decodeEvent(.succeeded(attemptIndex: attempt, parts: parts)))
                return parts

            case .failure(let originalText, let errors):
                lastErrors = errors
                continuation.yield(.decodeEvent(.failed(attemptIndex: attempt, text: originalText, errors: errors)))

                if attempt == a2uiConfiguration.maxParseRetries {
                    continuation.yield(.decodeEvent(.retriesExhausted(attempts: attempt + 1, lastErrors: errors)))
                    return [A2UIResponsePart(text: originalText)]
                }

                let reasons = errors.map(\.message)
                continuation.yield(.decodeEvent(.retryRequested(nextAttemptIndex: attempt + 1, reasons: reasons)))

                messages.append(.assistant(originalText))
                messages.append(.user(
                    A2UIResponseParser.formatRetryPrompt(originalText: originalText, errors: errors)
                ))

                let response = try await client.executeAgentStep(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    tools: ToolSet {},
                    toolChoice: nil,
                    responseSchema: nil,
                    thinkingMode: .disabled,
                    reasoningEffort: nil,
                    maxTokens: nil,
                    cachePolicy: .implicit
                )

                continuation.yield(.thinking(response))
                currentText = response.text
            }
        }

        continuation.yield(.decodeEvent(.retriesExhausted(attempts: a2uiConfiguration.maxParseRetries + 1, lastErrors: lastErrors)))
        return [A2UIResponsePart(text: currentText)]
    }
}
