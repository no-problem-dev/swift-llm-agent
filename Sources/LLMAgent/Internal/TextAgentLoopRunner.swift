import Foundation
import LLMClient
import LLMTool

// MARK: - TextAgentLoopRunner

/// 構造化出力を要求しないエージェントループ。
///
/// `AgentLoopRunner<Output>` と異なり `Output: StructuredProtocol` 制約も
/// `finalOutput` フェーズも持たない。LLM の応答にツール呼び出しがなくなったら、
/// その応答テキストを `.finalText(text)` として発行して完了する。
///
/// A2UI のように「LLM のテキスト応答中の JSON コードブロックを抽出して使う」
/// パターンや、純粋なチャット応答用途に適している。
internal actor TextAgentLoopRunner<Client: AgentCapableClient>
    where Client.Model: Sendable
{
    private let client: Client
    private let model: Client.Model
    private let context: AgentContext
    private let terminationPolicy: any AgentTerminationPolicy
    private let stateManager: AgentLoopStateManager

    private var pendingEvents: [PendingEvent] = []
    private var phase: TextPhase = .toolUse

    init(client: Client, model: Client.Model, context: AgentContext, configuration: AgentConfiguration) {
        self.client = client
        self.model = model
        self.context = context
        self.stateManager = AgentLoopStateManager(configuration: configuration)
        self.terminationPolicy = TerminationPolicyFactory.make(from: configuration)
    }

    // MARK: - Public Interface

    func nextStep() async throws -> AgentTextStep? {
        try Task.checkCancellation()

        if let event = consumePendingEvent() {
            return event
        }

        if phase == .completed {
            return nil
        }

        if await stateManager.isAtStepLimit {
            // 上限到達: 最後の assistant メッセージを finalText として返して完了。
            let lastText = await context.getLastAssistantText()
            phase = .completed
            await context.markCompleted()
            if !lastText.isEmpty {
                return .finalText(lastText)
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
        phase == .completed ? .completed : .toolUse
    }

    func cancel() {
        phase = .completed
    }

    // MARK: - Decision Handling

    private func handleDecision(
        _ decision: TerminationDecision,
        response: LLMResponse
    ) async throws -> AgentTextStep? {
        switch decision {
        case .continueWithTools(let calls):
            return try await processToolCalls(calls)

        case .continueWithThinking:
            // テキスト応答だが、ツール呼び出しもなくループを完了する余地がある状況。
            // ツールが空 or 最終応答とみなして完了。
            return try await finalizeAsText(response: response)

        case .terminateWithOutput(let text):
            return try await finalize(text: text)

        case .terminateImmediately(let reason):
            return try await handleImmediateTermination(reason, response: response)
        }
    }

    private func processToolCalls(_ calls: [ToolCall]) async throws -> AgentTextStep? {
        let config = await context.getConfiguration()

        if config.autoExecuteTools {
            for call in calls {
                await stateManager.recordToolCall(call)
                pendingEvents.append(.toolCall(call))
            }

            let results: [ToolResponse]
            if calls.count <= 1 || !config.parallelToolExecution {
                var sequential: [ToolResponse] = []
                for call in calls {
                    try Task.checkCancellation()
                    let result = await executeToolSafely(call)
                    sequential.append(result)
                    pendingEvents.append(.toolResult(result))
                }
                results = sequential
            } else {
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
                                    content: .success(result.stringValue)
                                ))
                            } catch {
                                return (index, ToolResponse(
                                    callId: call.id, name: call.name,
                                    content: .failure("Error: \(error.localizedDescription)")
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
            // 自動実行オフ: 完了扱い。
            phase = .completed
            await context.markCompleted()
            return nil
        }
    }

    private func finalizeAsText(response: LLMResponse) async throws -> AgentTextStep? {
        let text = await context.extractText(from: response)
        return try await finalize(text: text)
    }

    private func finalize(text: String) async throws -> AgentTextStep? {
        phase = .completed
        await context.markCompleted()
        return .finalText(text)
    }

    private func handleImmediateTermination(_ reason: TerminationReason, response: LLMResponse) async throws -> AgentTextStep? {
        phase = .completed
        await context.markCompleted()

        switch reason {
        case .completed, .emptyResponse, .unexpectedStopReason:
            let text = await context.extractText(from: response)
            return text.isEmpty ? nil : .finalText(text)

        case .maxStepsReached:
            let lastText = await context.getLastAssistantText()
            if !lastText.isEmpty {
                return .finalText(lastText)
            }
            throw AgentError.maxStepsExceeded(steps: stateManager.maxSteps)

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

    private func consumePendingEvent() -> AgentTextStep? {
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
        var messages = await context.getMessages()
        messages.sanitizeOrphanedToolUses()
        let systemPrompt = await context.getSystemPrompt()
        let config = await context.getConfiguration()

        let tools = await context.getTools()
        do {
            return try await client.executeAgentStep(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                tools: tools,
                toolChoice: tools.isEmpty ? nil : .auto,
                responseSchema: nil, // テキスト出力モード: 構造化スキーマは要求しない
                thinkingMode: config.thinkingMode,
                maxTokens: config.maxTokens
            )
        } catch let error as LLMError {
            throw AgentError.llmError(error)
        }
    }

    private func executeToolSafely(_ call: ToolCall) async -> ToolResponse {
        do {
            let result = try await context.executeTool(named: call.name, with: call.arguments)
            return ToolResponse(
                callId: call.id,
                name: call.name,
                content: .success(result.stringValue)
            )
        } catch {
            return ToolResponse(
                callId: call.id,
                name: call.name,
                content: .failure("Error: \(error.localizedDescription)")
            )
        }
    }
}

// MARK: - TextPhase

internal enum TextPhase: Sendable, Equatable {
    case toolUse
    case completed
}
