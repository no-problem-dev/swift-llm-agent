import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - LoopPhase

/// エージェントループの内部フェーズ
private enum LoopPhase: Sendable {
    case toolUse
    case finalOutput(retryCount: Int)
}

// MARK: - FinalOutputConstants

private enum FinalOutputConstants {
    static let maxDecodeRetries: Int = 2
    static let requestMessage = "Please provide your final response in the required JSON format."
}

// MARK: - ConversationalAgentSession

/// 会話型エージェントセッション（純粋 LLM ループエンジン）
///
/// セッションは**会話履歴のみ**を保持し、ツール・システムプロンプト・
/// エージェント設定はターンごとに `TurnConfiguration` として渡されます。
///
/// チャンネル連携やインタラクションは `OrchestratorAgent` / `UIAgent` が担当し、
/// このクラスは LLM ループの実行に専念します。
public actor ConversationalAgentSession<Client: AgentCapableClient>: ConversationalAgentSessionProtocol
    where Client.Model: Sendable
{
    // MARK: - Properties

    private let client: Client
    private var messages: [LLMMessage] = []
    private var interruptQueue: [String] = []

    /// 現在のセッション状態
    public private(set) var status: SessionStatus = .idle

    // MARK: - Initialization

    public init(
        client: Client,
        initialMessages: [LLMMessage] = []
    ) {
        self.client = client
        self.messages = initialMessages
    }

    // MARK: - Protocol Conformance: Properties

    public var running: Bool {
        status.isActive
    }

    public var turnCount: Int {
        messages.filter { $0.role == .user }.count
    }

    // MARK: - Protocol Conformance: Context Injection

    /// チャンネルメッセージを会話履歴に挿入
    ///
    /// 実行中のループがある場合、次の LLM コールに自動的に含まれる。
    public func injectContext(_ text: String) {
        messages.append(LLMMessage.user(text))
    }

    // MARK: - Protocol Conformance: Interrupt API

    public func interrupt(_ message: String) {
        guard status.canInterrupt else { return }
        interruptQueue.append(message)
    }

    public func clearInterrupts() {
        interruptQueue.removeAll()
    }

    // MARK: - Protocol Conformance: Session Management

    public func getMessages() -> [LLMMessage] {
        messages
    }

    public func clear() async {
        guard status.canClear else { return }
        messages.removeAll()
        interruptQueue.removeAll()
        status = .idle
    }

    public func cancel() async {
        guard status.canCancel else { return }
        status = .cancelled
        interruptQueue.removeAll()
    }

    // MARK: - Protocol Conformance: Core API

    nonisolated public func run<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type = Output.self
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeLoop(
                    input: input,
                    model: model,
                    turn: turn,
                    outputType: Output.self,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Resume API

    nonisolated public func resume<Output: StructuredProtocol>(
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeResumeLoop(
                    model: model,
                    turn: turn,
                    outputType: Output.self,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Prefill API

    nonisolated public func runWithPrefill<Output: StructuredProtocol>(
        prefill: [LLMMessage],
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type = Output.self
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executePrefillLoop(
                    prefill: prefill,
                    model: model,
                    turn: turn,
                    outputType: Output.self,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Internal Loop

    private func executePrefillLoop<Output: StructuredProtocol>(
        prefill: [LLMMessage],
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        guard status.canRun else {
            continuation.finish(throwing: ConversationalAgentError.sessionAlreadyRunning)
            return
        }
        messages.append(contentsOf: prefill)
        status = .running
        await runAgentLoop(model: model, turn: turn, outputType: Output.self, continuation: continuation)
    }

    private func executeResumeLoop<Output: StructuredProtocol>(
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        guard status.canResume else {
            let error = ConversationalAgentError.sessionAlreadyRunning
            continuation.finish(throwing: error)
            return
        }

        guard !messages.isEmpty else {
            let error = ConversationalAgentError.invalidState("No conversation history to resume. Use run() instead.")
            continuation.finish(throwing: error)
            return
        }

        repairIncompleteToolUses()

        let continueMsg = "Please continue where you left off."
        messages.append(LLMMessage.user(continueMsg))

        status = .running
        let step = AgentStep.userMessage(continueMsg)
        continuation.yield(.running(step: step))

        await runAgentLoop(
            model: model,
            turn: turn,
            outputType: Output.self,
            continuation: continuation
        )
    }

    private func executeLoop<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        guard status.canRun else {
            let error = ConversationalAgentError.sessionAlreadyRunning
            continuation.finish(throwing: error)
            return
        }

        messages.append(input.toLLMMessage())

        let userMessageText = input.prompt.render()
        status = .running
        let step = AgentStep.userMessage(userMessageText)
        continuation.yield(.running(step: step))

        await runAgentLoop(
            model: model,
            turn: turn,
            outputType: Output.self,
            continuation: continuation
        )
    }

    private func repairIncompleteToolUses() {
        var pendingToolUseIds: [(id: String, name: String)] = []

        for message in messages {
            if message.role == .assistant {
                for content in message.contents {
                    if case .toolUse(let id, let name, _) = content {
                        pendingToolUseIds.append((id: id, name: name))
                    }
                }
            } else if message.role == .user {
                for content in message.contents {
                    if case .toolResult(let toolCallId, _, _, _) = content {
                        pendingToolUseIds.removeAll { $0.id == toolCallId }
                    }
                }
            }
        }

        if !pendingToolUseIds.isEmpty {
            let dummyResults = pendingToolUseIds.map { toolUse in
                LLMMessage.MessageContent.toolResult(
                    toolCallId: toolUse.id,
                    name: toolUse.name,
                    content: "Session was interrupted. Continuing from where we left off.",
                    isError: false
                )
            }
            messages.append(LLMMessage(role: .user, contents: dummyResults))
        }
    }

    private func runAgentLoop<Output: StructuredProtocol>(
        model: Client.Model,
        turn: TurnConfiguration,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        let tools = turn.tools
        let systemPrompt = turn.systemPrompt
        let executionPolicy = turn.executionPolicy
        let configuration = turn.agentConfiguration

        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps
        let maxToolCallsPerTool = configuration.maxToolCallsPerTool
        var toolCallCounts: [String: Int] = [:]
        // ツールがなく構造化出力が必要な場合、toolUse フェーズをスキップして
        // 直接 finalOutput フェーズで開始する（responseSchema 付き LLM 呼び出し）。
        // toolUse フェーズは responseSchema を送信しないため、
        // ツール空の場合にステップを浪費するだけで意味がない。
        var loopPhase: LoopPhase = (tools.isEmpty && !configuration.skipFinalOutput)
            ? .finalOutput(retryCount: 0)
            : .toolUse

        do {
            while step < maxSteps {
                try Task.checkCancellation()
                step += 1

                // ソフトリミット注入
                if step == softMaxSteps, case .toolUse = loopPhase {
                    let softLimitMsg = "IMPORTANT: You are running low on remaining steps (\(maxSteps - step) left). " +
                        "Wrap up your current work and produce your final output now. " +
                        "Do not start new tool calls unless absolutely necessary."
                    messages.append(LLMMessage.user(softLimitMsg))
                    let interruptedStep = AgentStep.interrupted(softLimitMsg)
                    continuation.yield(.running(step: interruptedStep))
                }

                // 割り込みチェックポイント（toolUse フェーズのみ）
                if case .toolUse = loopPhase, !interruptQueue.isEmpty {
                    for interruptMsg in interruptQueue {
                        messages.append(LLMMessage.user(interruptMsg))
                        let interruptedStep = AgentStep.interrupted(interruptMsg)
                        continuation.yield(.running(step: interruptedStep))
                    }
                    interruptQueue.removeAll()
                }

                let thinkingStep = AgentStep.thinking
                continuation.yield(.running(step: thinkingStep))

                messages.sanitizeOrphanedToolUses()

                let response: LLMResponse
                do {
                    switch loopPhase {
                    case .toolUse:
                        var fullResponse: LLMResponse?
                        for try await event in client.streamAgentStep(
                            messages: messages,
                            model: model,
                            systemPrompt: systemPrompt,
                            tools: tools,
                            toolChoice: tools.isEmpty ? nil : .auto,
                            responseSchema: nil,
                            thinkingMode: configuration.thinkingMode,
                            maxTokens: configuration.maxTokens
                        ) {
                            switch event {
                            case .delta(let delta):
                                switch delta {
                                case .thinkingDelta(let text):
                                    let deltaStep = AgentStep.thinkingDelta(text)
                                    continuation.yield(.running(step: deltaStep))
                                case .textDelta:
                                    break
                                }
                            case .completed(let resp):
                                fullResponse = resp
                            }
                        }
                        guard let completed = fullResponse else {
                            throw ConversationalAgentError.invalidState("No response received from streaming")
                        }
                        try Task.checkCancellation()
                        response = completed

                    case .finalOutput:
                        var fullResponse: LLMResponse?
                        for try await event in client.streamAgentStep(
                            messages: messages,
                            model: model,
                            systemPrompt: systemPrompt,
                            tools: ToolSet {},
                            toolChoice: nil,
                            responseSchema: Output.jsonSchema,
                            thinkingMode: configuration.thinkingMode,
                            maxTokens: configuration.maxTokens
                        ) {
                            switch event {
                            case .delta(let delta):
                                switch delta {
                                case .thinkingDelta(let text):
                                    let deltaStep = AgentStep.thinkingDelta(text)
                                    continuation.yield(.running(step: deltaStep))
                                case .textDelta:
                                    break
                                }
                            case .completed(let resp):
                                fullResponse = resp
                            }
                        }
                        guard let completed = fullResponse else {
                            throw ConversationalAgentError.invalidState("No response received from streaming")
                        }
                        try Task.checkCancellation()
                        response = completed
                    }
                } catch let error as LLMError {
                    throw ConversationalAgentError.llmError(error)
                }

                addAssistantResponse(response)

                switch loopPhase {
                case .toolUse:
                    let toolCalls = extractToolCalls(from: response)

                    if toolCalls.isEmpty {
                        if configuration.skipFinalOutput {
                            let text = extractTextContent(from: response)
                            status = .idle
                            continuation.yield(.completedText(text: text))
                            continuation.finish()
                            return
                        } else if !tools.isEmpty {
                            loopPhase = .finalOutput(retryCount: 0)
                            addFinalOutputRequest()
                            continue
                        } else {
                            // ツールなし: まず直接デコードを試み、
                            // 失敗時は finalOutput（responseSchema 付き）にフォールスルー
                            if let output = try? decodeOutput(response, as: Output.self) {
                                status = .idle
                                continuation.yield(.completed(output: output))
                                continuation.finish()
                                return
                            } else {
                                loopPhase = .finalOutput(retryCount: 0)
                                addFinalOutputRequest()
                                continue
                            }
                        }
                    }

                    // 同一ツールの呼び出し回数制限チェック
                    if let maxPerTool = maxToolCallsPerTool {
                        for call in toolCalls {
                            toolCallCounts[call.name, default: 0] += 1
                        }
                        if let (overTool, overCount) = toolCallCounts.first(where: { $0.value > maxPerTool }) {
                            let limitMsg = "Tool '\(overTool)' has been called \(overCount) times, exceeding the limit of \(maxPerTool). " +
                                "Produce your final answer using the information you already have."
                            messages.append(LLMMessage.user(limitMsg))
                            let interruptedStep = AgentStep.interrupted(limitMsg)
                            continuation.yield(.running(step: interruptedStep))

                            // 全ツール呼び出しにエラー応答を返す（tool_use/tool_result の対応を維持）
                            let limitResults = toolCalls.map { call in
                                ToolResponse(
                                    callId: call.id, name: call.name,
                                    output: "Error: Tool call limit exceeded for '\(overTool)' (\(maxPerTool) max). Use existing results.", isError: true
                                )
                            }
                            addToolResults(limitResults)
                            continue
                        }
                    }

                    // ツール呼び出しがある場合
                    if configuration.autoExecuteTools {
                        for call in toolCalls {
                            let toolCallStep = AgentStep.toolCall(call)
                            continuation.yield(.running(step: toolCallStep))
                        }

                        // ポリシー評価
                        var approvedCalls: [ToolCall] = []
                        var policyDeniedResults: [ToolResponse] = []

                        if let policy = executionPolicy {
                            for call in toolCalls {
                                let decision = await policy.evaluate(call, tools: tools)
                                switch decision {
                                case .allow:
                                    approvedCalls.append(call)
                                case .deny(let reason):
                                    let result = ToolResponse(
                                        callId: call.id, name: call.name,
                                        output: "Denied: \(reason)", isError: true
                                    )
                                    policyDeniedResults.append(result)
                                    let resultStep = AgentStep.toolResult(result)
                                    continuation.yield(.running(step: resultStep))
                                case .requiresApproval:
                                    // チャンネルアーキテクチャでは承認はエージェント層で処理
                                    // ここでは deny にフォールバック
                                    let result = ToolResponse(
                                        callId: call.id, name: call.name,
                                        output: "Denied: Requires approval (not available in current context)", isError: true
                                    )
                                    policyDeniedResults.append(result)
                                    let resultStep = AgentStep.toolResult(result)
                                    continuation.yield(.running(step: resultStep))
                                }
                            }
                        } else {
                            approvedCalls = toolCalls
                        }

                        // ツール実行
                        let toolResults: [ToolResponse]
                        if approvedCalls.count <= 1 {
                            var results: [ToolResponse] = []
                            for call in approvedCalls {
                                let result = await executeToolSafely(call, tools: tools)
                                try Task.checkCancellation()
                                results.append(result)
                                let resultStep = AgentStep.toolResult(result)
                                continuation.yield(.running(step: resultStep))
                            }
                            toolResults = results + policyDeniedResults
                        } else {
                            let toolSet = tools
                            let executed = await withTaskGroup(of: (Int, ToolResponse).self) { group in
                                for (index, call) in approvedCalls.enumerated() {
                                    group.addTask {
                                        do {
                                            let result = try await toolSet.execute(
                                                toolNamed: call.name, with: call.arguments
                                            )
                                            return (index, ToolResponse(
                                                callId: call.id, name: call.name,
                                                output: result.stringValue, isError: result.isError,
                                                mediaContents: result.mediaContents
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
                                    let resultStep = AgentStep.toolResult(pair.1)
                                    continuation.yield(.running(step: resultStep))
                                    indexed.append(pair)
                                }
                                return indexed.sorted(by: { $0.0 < $1.0 }).map(\.1)
                            }
                            toolResults = executed + policyDeniedResults
                        }

                        if !toolResults.isEmpty {
                            addToolResults(toolResults)
                        }
                    } else {
                        continuation.finish()
                        return
                    }

                case .finalOutput(let retryCount):
                    do {
                        let output = try decodeOutput(response, as: Output.self)
                        status = .idle
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    } catch {
                        let newRetryCount = retryCount + 1
                        if newRetryCount >= FinalOutputConstants.maxDecodeRetries {
                            throw ConversationalAgentError.outputDecodingFailed(error)
                        }
                        loopPhase = .finalOutput(retryCount: newRetryCount)
                        addFinalOutputRequest()
                        continue
                    }
                }
            }

            // ハードリミット到達: graceful degradation
            let lastText = extractLastAssistantText()
            if configuration.skipFinalOutput, !lastText.isEmpty {
                status = .idle
                continuation.yield(.completedText(text: lastText))
                continuation.finish()
            } else if !lastText.isEmpty,
               let output = try? JSONDecoder.snakeCaseDecoder.decode(Output.self, from: Data(lastText.utf8)) {
                status = .idle
                continuation.yield(.completed(output: output))
                continuation.finish()
            } else {
                let error = ConversationalAgentError.maxStepsExceeded(steps: maxSteps)
                status = .failed(error.localizedDescription)
                continuation.yield(.failed(error: error.localizedDescription))
                continuation.finish(throwing: error)
            }

        } catch is CancellationError {
            status = .cancelled
            continuation.yield(.paused)
            continuation.finish()
        } catch let error as ConversationalAgentError {
            status = .failed(error.localizedDescription)
            continuation.yield(.failed(error: error.localizedDescription))
            continuation.finish(throwing: error)
        } catch {
            let wrappedError = ConversationalAgentError.invalidState(error.localizedDescription)
            status = .failed(wrappedError.localizedDescription)
            continuation.yield(.failed(error: wrappedError.localizedDescription))
            continuation.finish(throwing: wrappedError)
        }
    }

    // MARK: - Private Helpers

    private func addAssistantResponse(_ response: LLMResponse) {
        var contents: [LLMMessage.MessageContent] = []

        for block in response.content {
            switch block {
            case .text(let text):
                if !text.isEmpty {
                    contents.append(.text(text))
                }
            case .toolUse(let id, let name, let input):
                contents.append(.toolUse(id: id, name: name, input: input))
            case .thinking(let text, let signature):
                contents.append(.thinking(text: text, signature: signature))
            case .image, .audio:
                break
            }
        }

        if !contents.isEmpty {
            messages.append(LLMMessage(role: .assistant, contents: contents))
        }
    }

    private func addToolResults(_ results: [ToolResponse], extraImages: [ImageContent] = []) {
        guard !results.isEmpty else { return }

        var contents = results.map { result in
            LLMMessage.MessageContent.toolResult(
                toolCallId: result.callId,
                name: result.name,
                content: result.output,
                isError: result.isError
            )
        }
        let allMedia = results.flatMap(\.mediaContents) + extraImages
        contents += allMedia.map { .image($0) }
        messages.append(LLMMessage(role: .user, contents: contents))
    }

    private func extractToolCalls(from response: LLMResponse) -> [ToolCall] {
        response.content.compactMap { block in
            guard case .toolUse(let id, let name, let input) = block else {
                return nil
            }
            return ToolCall(id: id, name: name, arguments: input)
        }
    }

    private func executeToolSafely(_ call: ToolCall, tools: ToolSet) async -> ToolResponse {
        do {
            let result = try await tools.execute(toolNamed: call.name, with: call.arguments)
            return ToolResponse(
                callId: call.id,
                name: call.name,
                output: result.stringValue,
                isError: result.isError,
                mediaContents: result.mediaContents
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

    private func decodeOutput<Output: StructuredProtocol>(
        _ response: LLMResponse,
        as type: Output.Type
    ) throws -> Output {
        let text = extractTextContent(from: response)
        return try decodeOutput(text, as: type)
    }

    private func decodeOutput<Output: StructuredProtocol>(
        _ text: String,
        as type: Output.Type
    ) throws -> Output {
        guard !text.isEmpty else {
            throw ConversationalAgentError.outputDecodingFailed(
                NSError(domain: "ConversationalAgentSession", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Response contains no text"
                ])
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Output.self, from: Data(text.utf8))
    }

    private func extractTextContent(from response: LLMResponse) -> String {
        response.content.compactMap { block -> String? in
            if case .text(let value) = block { return value }
            return nil
        }.joined()
    }

    private func addFinalOutputRequest() {
        let message = LLMMessage.user(FinalOutputConstants.requestMessage)
        messages.append(message)
    }

    private func extractLastAssistantText() -> String {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else {
            return ""
        }
        return lastAssistant.contents.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()
    }
}

// MARK: - JSONDecoder Extension

private extension JSONDecoder {
    static let snakeCaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
