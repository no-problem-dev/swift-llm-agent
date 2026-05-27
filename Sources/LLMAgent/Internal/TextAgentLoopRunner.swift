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

    private var deferredFinalStep: AgentTextStep?

    /// `.toolCall` を流したがまだ実行していない呼び出し。実行を次の `nextStep` まで遅延させ、
    /// `.toolCall` →（実行）→ `.toolResult` の間に実体時間を生む。
    private var pendingToolExecutions: [ToolCall] = []

    private var executedToolResults: [ToolResponse] = []
    private var lastExecutedBatch: [ToolResponse] = []

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

        // .toolCall を流し切ってから、ここで初めてツールを実行して .toolResult を流す。
        if let result = try await nextToolResult() {
            return result
        }

        if let final = deferredFinalStep {
            deferredFinalStep = nil
            return final
        }

        if phase == .completed {
            return nil
        }

        if await stateManager.isAtStepLimit {
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

        // usage を先に流すため、後続ステップは pending / deferred に退避してから .thinking を返す。
        if let following = try await handleDecision(decision, response: response) {
            switch following {
            case .toolCall(let call):
                pendingEvents.insert(.toolCall(call), at: 0)
            case .toolResult(let result):
                pendingEvents.insert(.toolResult(result), at: 0)
            case .thinking, .finalText:
                deferredFinalStep = following
            }
        }

        return .thinking(response)
    }

    /// 未実行のツール呼び出しがあれば実行し、結果を 1 件ずつ `.toolResult` として返す。
    private func nextToolResult() async throws -> AgentTextStep? {
        if executedToolResults.isEmpty, !pendingToolExecutions.isEmpty {
            let calls = pendingToolExecutions
            pendingToolExecutions = []
            executedToolResults = try await executeTools(calls)
        }

        guard !executedToolResults.isEmpty else {
            return nil
        }

        let result = executedToolResults.removeFirst()
        if executedToolResults.isEmpty {
            await context.addToolResults(lastExecutedBatch)
            lastExecutedBatch = []
        }
        return .toolResult(result)
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

    /// `.toolCall` を pending に積み、実行は遅延キューへ回す。最初の `.toolCall` を返す。
    private func processToolCalls(_ calls: [ToolCall]) async throws -> AgentTextStep? {
        guard await context.getConfiguration().autoExecuteTools else {
            phase = .completed
            await context.markCompleted()
            return nil
        }

        for call in calls {
            await stateManager.recordToolCall(call)
            pendingEvents.append(.toolCall(call))
        }
        pendingToolExecutions = calls
        return consumePendingEvent()
    }

    /// ツールを実行して結果を返す。`context` への反映は呼び出し側（`nextToolResult`）が行う。
    private func executeTools(_ calls: [ToolCall]) async throws -> [ToolResponse] {
        let config = await context.getConfiguration()

        if calls.count <= 1 || !config.parallelToolExecution {
            var results: [ToolResponse] = []
            for call in calls {
                try Task.checkCancellation()
                results.append(await executeToolSafely(call))
            }
            lastExecutedBatch = results
            return results
        }

        let toolSet = await context.getTools()
        let results = await withTaskGroup(of: (Int, ToolResponse).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask {
                    do {
                        let result = try await toolSet.execute(toolNamed: call.name, with: call.arguments)
                        return (index, ToolResponse(callId: call.id, name: call.name, content: .success(result.stringValue)))
                    } catch {
                        return (index, ToolResponse(callId: call.id, name: call.name, content: .failure("Error: \(error.localizedDescription)")))
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
        lastExecutedBatch = results
        return results
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
        case .thinking(let response):
            return .thinking(response)
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
                reasoningEffort: config.reasoningEffort,
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
