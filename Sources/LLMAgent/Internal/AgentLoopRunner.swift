import Foundation
import LLMClient
import LLMTool

// MARK: - AgentLoopRunner

/// エージェントループの実行を管理する Actor
internal actor AgentLoopRunner<Client: AgentCapableClient, Output: StructuredProtocol>
    where Client.Model: Sendable
{
    private let client: Client
    private let model: Client.Model
    private let context: AgentContext
    private let terminationPolicy: any AgentTerminationPolicy
    private let stateManager: AgentLoopStateManager

    private var pendingEvents: [PendingEvent] = []
    private var phase: LoopPhase = .toolUse
    private let maxDecodeRetries: Int = AgentLoopConstants.maxDecodeRetries
    private var isCancelled: Bool = false

    init(client: Client, model: Client.Model, context: AgentContext, configuration: AgentConfiguration) {
        self.client = client
        self.model = model
        self.context = context
        self.stateManager = AgentLoopStateManager(configuration: configuration)
        self.terminationPolicy = TerminationPolicyFactory.make(from: configuration)
    }

    // MARK: - Public Interface

    func nextStep() async throws -> AgentStep<Output>? {
        try Task.checkCancellation()

        if isCancelled {
            return nil
        }

        if let event = consumePendingEvent() {
            return event
        }

        if phase == .completed {
            return nil
        }

        if await stateManager.isAtStepLimit {
            // Graceful degradation: 最後の assistant メッセージからデコードを試行
            let lastText = await context.getLastAssistantText()
            if !lastText.isEmpty {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let output = try? decoder.decode(Output.self, from: Data(lastText.utf8)) {
                    phase = .completed
                    await context.markCompleted()
                    return .finalResponse(output)
                }
            }
            throw AgentError.maxStepsExceeded(steps: stateManager.maxSteps)
        }

        try await stateManager.incrementStep()

        let response = try await sendRequest()
        try Task.checkCancellation()
        await context.addAssistantResponse(response)

        let decision = await terminationPolicy.shouldTerminate(
            response: response,
            context: stateManager
        )

        return try await handleDecision(decision, response: response)
    }

    func currentPhase() -> AgentExecutionPhase {
        phase.toPublic
    }

    func cancel() {
        isCancelled = true
        phase = .completed
    }

    // MARK: - Decision Handling

    private func handleDecision(
        _ decision: TerminationDecision,
        response: LLMResponse
    ) async throws -> AgentStep<Output>? {
        switch decision {
        case .continueWithTools(let calls):
            return try await processToolCalls(calls)

        case .continueWithThinking:
            return .thinking(response)

        case .terminateWithOutput(let text):
            return try await decodeFinalOutput(text, response: response)

        case .terminateImmediately(let reason):
            return try handleImmediateTermination(reason)
        }
    }

    private func processToolCalls(_ calls: [ToolCall]) async throws -> AgentStep<Output>? {
        let config = await context.getConfiguration()

        if config.autoExecuteTools {
            // 全ツールコールを記録・イベント化
            for call in calls {
                await stateManager.recordToolCall(call)
                pendingEvents.append(.toolCall(call))
            }

            let results: [ToolResponse]
            if calls.count <= 1 || !config.parallelToolExecution {
                // 逐次実行（1件以下 or 順序保証が必要な場合）
                var sequential: [ToolResponse] = []
                for call in calls {
                    try Task.checkCancellation()
                    let result = await executeToolSafely(call)
                    sequential.append(result)
                    pendingEvents.append(.toolResult(result))
                }
                results = sequential
            } else {
                // 2件以上かつ並列実行許可時
                let toolSet = await context.getTools()
                results = await withTaskGroup(of: (Int, ToolResponse).self) { group in
                    for (index, call) in calls.enumerated() {
                        group.addTask {
                            do {
                                let result = try await toolSet.execute(
                                    toolNamed: call.name, with: call.arguments
                                )
                                return (index, ToolResponse(
                                    callId: call.id, name: call.name,
                                    output: result.stringValue, isError: result.isError
                                ))
                            } catch {
                                return (index, ToolResponse(
                                    callId: call.id, name: call.name,
                                    output: "Error: \(error.localizedDescription)", isError: true
                                ))
                            }
                        }
                    }
                    var indexed: [(Int, ToolResponse)] = []
                    for await pair in group {
                        guard !Task.isCancelled else { break }
                        indexed.append(pair)
                    }
                    return indexed.sorted(by: { $0.0 < $1.0 }).map(\.1)
                }
                for result in results {
                    pendingEvents.append(.toolResult(result))
                }
            }

            await context.addToolResults(results)
            return consumePendingEvent()
        } else {
            phase = .completed
            await context.markCompleted()
            return nil
        }
    }

    private func decodeFinalOutput(_ text: String, response: LLMResponse) async throws -> AgentStep<Output>? {
        switch phase {
        case .toolUse:
            let tools = await context.getTools()
            if !tools.isEmpty {
                phase = .finalOutput(retryCount: 0)
                await context.addFinalOutputRequest()
                return .thinking(response)
            }
            return try decodeAndComplete(text)

        case .finalOutput(let retryCount):
            do {
                return try decodeAndComplete(text)
            } catch {
                let newRetryCount = retryCount + 1
                if newRetryCount >= maxDecodeRetries {
                    throw AgentError.outputDecodingFailed(error)
                }
                phase = .finalOutput(retryCount: newRetryCount)
                await context.addFinalOutputRequest()
                return .thinking(response)
            }

        case .completed:
            return nil
        }
    }

    private func decodeAndComplete(_ text: String) throws -> AgentStep<Output> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(Output.self, from: Data(text.utf8))
        phase = .completed
        Task { await context.markCompleted() }
        return .finalResponse(output)
    }

    private func handleImmediateTermination(_ reason: TerminationReason) throws -> AgentStep<Output>? {
        phase = .completed
        Task { await context.markCompleted() }

        switch reason {
        case .completed, .emptyResponse, .maxStepsReached, .unexpectedStopReason:
            return nil

        case .duplicateToolCallDetected(let toolName, let count):
            throw AgentError.terminatedByPolicy(
                "Duplicate tool call detected: '\(toolName)' called \(count) times with same input"
            )

        case .maxToolCallsPerToolReached(let toolName, let count):
            throw AgentError.terminatedByPolicy(
                "Tool call limit reached: '\(toolName)' called \(count) times total"
            )
        }
    }

    // MARK: - Helper Methods

    private func consumePendingEvent() -> AgentStep<Output>? {
        guard !pendingEvents.isEmpty else { return nil }

        let event = pendingEvents.removeFirst()
        switch event {
        case .toolCall(let info):
            return .toolCall(info)
        case .toolResult(let info):
            return .toolResult(info)
        }
    }

    private func sendRequest() async throws -> LLMResponse {
        // クラッシュ等で tool_result が欠落した場合に備えてメッセージ履歴を修復
        var messages = await context.getMessages()
        messages.sanitizeOrphanedToolUses()
        let systemPrompt = await context.getSystemPrompt()
        let config = await context.getConfiguration()

        switch phase {
        case .toolUse:
            let tools = await context.getTools()
            let shouldRequestStructuredOutput = tools.isEmpty
            let responseSchema: JSONSchema? = shouldRequestStructuredOutput ? Output.jsonSchema : nil

            do {
                return try await client.executeAgentStep(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    toolChoice: tools.isEmpty ? nil : .auto,
                    responseSchema: responseSchema,
                    maxTokens: config.maxTokens
                )
            } catch let error as LLMError {
                throw AgentError.llmError(error)
            }

        case .finalOutput:
            do {
                return try await client.executeAgentStep(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    tools: ToolSet {},
                    toolChoice: nil,
                    responseSchema: Output.jsonSchema,
                    maxTokens: config.maxTokens
                )
            } catch let error as LLMError {
                throw AgentError.llmError(error)
            }

        case .completed:
            throw AgentError.invalidState("sendRequest called in completed phase")
        }
    }

    private func executeToolSafely(_ call: ToolCall) async -> ToolResponse {
        do {
            let result = try await context.executeTool(named: call.name, with: call.arguments)
            return ToolResponse(
                callId: call.id,
                name: call.name,
                output: result.stringValue,
                isError: result.isError
            )
        } catch {
            return ToolResponse(
                callId: call.id,
                name: call.name,
                output: "Error: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
