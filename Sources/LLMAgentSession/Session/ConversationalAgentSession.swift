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

/// 会話型エージェントセッション
///
/// セッションは**会話履歴のみ**を保持し、ツール・システムプロンプト・
/// エージェント設定はターンごとに `TurnConfiguration` として渡されます。
///
/// ## 設計原則
///
/// Claude Code / Agent SDK の設計に倣い、**セッション = 会話履歴の管理者**、
/// **設定 = ターンごとのパラメータ**として分離しています。
/// これにより、ターン間でモデル・ツール・システムプロンプト・出力型を自由に変更できます。
///
/// ## 使用例
///
/// ```swift
/// let session = ConversationalAgentSession(client: anthropicClient)
///
/// let turnConfig = TurnConfiguration(
///     systemPrompt: SystemPrompt { "リサーチアシスタントです。" },
///     tools: ToolSet { WebSearchTool() },
///     interactiveMode: true
/// )
///
/// // 1st turn
/// for try await phase in session.run(
///     input: "AIについて調査して",
///     model: .sonnet,
///     turn: turnConfig,
///     outputType: ResearchResult.self
/// ) {
///     // ...
/// }
///
/// // 2nd turn - ツールを変更して再開
/// var newConfig = turnConfig
/// newConfig.tools = newConfig.tools.appending(CodeAnalysisTool())
/// for try await phase in session.run(
///     input: "コード例も分析して",
///     model: .haiku,  // モデルも変更可能
///     turn: newConfig,
///     outputType: ResearchResult.self
/// ) {
///     // ...
/// }
/// ```
public actor ConversationalAgentSession<Client: AgentCapableClient>: ConversationalAgentSessionProtocol
    where Client.Model: Sendable
{
    // MARK: - Properties

    private let client: Client
    private var messages: [LLMMessage] = []
    private var interruptQueue: [String] = []

    /// 現在のセッション状態
    public private(set) var status: SessionStatus = .idle

    /// 保留中の ask_user ツール呼び出し
    private var pendingAskUserCall: ToolCall?
    private var answerContinuation: CheckedContinuation<String, Never>?
    private var askUserCallCount: Int = 0

    // MARK: - Initialization

    /// セッションを初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - initialMessages: 復元する会話履歴（オプション）
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

    public func clear() {
        guard status.canClear else { return }
        messages.removeAll()
        interruptQueue.removeAll()
        status = .idle
    }

    public func cancel() {
        guard status.canCancel else { return }
        status = .paused
        interruptQueue.removeAll()
        pendingAskUserCall = nil

        if let continuation = answerContinuation {
            answerContinuation = nil
            continuation.resume(returning: "")
        }
    }

    // MARK: - Protocol Conformance: User Interaction API

    public var waitingForAnswer: Bool {
        status.canReply
    }

    public func reply(_ answer: String) {
        guard status.canReply, let continuation = answerContinuation else { return }
        answerContinuation = nil
        continuation.resume(returning: answer)
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

    // MARK: - Internal Loop

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
        continuation.yield(.running(step: .userMessage(continueMsg)))

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
        continuation.yield(.running(step: .userMessage(userMessageText)))

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
        // TurnConfiguration からローカル変数に展開
        let tools = turn.interactiveMode ? turn.tools.appending(AskUserTool()) : turn.tools
        let systemPrompt = turn.systemPrompt
        let configuration = turn.agentConfiguration

        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps
        var loopPhase: LoopPhase = .toolUse

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
                    continuation.yield(.running(step: .interrupted(softLimitMsg)))
                }

                // 割り込みチェックポイント（toolUse フェーズのみ）
                if case .toolUse = loopPhase, !interruptQueue.isEmpty {
                    for interruptMsg in interruptQueue {
                        messages.append(LLMMessage.user(interruptMsg))
                        continuation.yield(.running(step: .interrupted(interruptMsg)))
                    }
                    interruptQueue.removeAll()
                }

                continuation.yield(.running(step: .thinking))

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
                            maxTokens: nil
                        ) {
                            switch event {
                            case .delta(let delta):
                                switch delta {
                                case .thinkingDelta(let text):
                                    continuation.yield(.running(step: .thinkingDelta(text)))
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
                            maxTokens: nil
                        ) {
                            switch event {
                            case .delta(let delta):
                                switch delta {
                                case .thinkingDelta(let text):
                                    continuation.yield(.running(step: .thinkingDelta(text)))
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
                            // skipFinalOutput: テキスト応答をそのまま返す
                            let text = extractTextContent(from: response)
                            status = .idle
                            do {
                                let output = try decodeOutput(text, as: Output.self)
                                continuation.yield(.completed(output: output))
                            } catch {
                                // デコード失敗時もテキストとして返す試み
                                throw ConversationalAgentError.outputDecodingFailed(error)
                            }
                            continuation.finish()
                            return
                        } else if !tools.isEmpty {
                            loopPhase = .finalOutput(retryCount: 0)
                            addFinalOutputRequest()
                            continue
                        } else {
                            if let output = try? decodeOutput(response, as: Output.self) {
                                status = .idle
                                continuation.yield(.completed(output: output))
                                continuation.finish()
                                return
                            } else {
                                let error = ConversationalAgentError.outputDecodingFailed(
                                    NSError(domain: "ConversationalAgentSession", code: -1, userInfo: [
                                        NSLocalizedDescriptionKey: "Failed to decode output"
                                    ])
                                )
                                status = .failed(error: error.localizedDescription)
                                continuation.yield(.failed(error: error.localizedDescription))
                                continuation.finish(throwing: error)
                                return
                            }
                        }
                    }

                    // ツール呼び出しがある場合
                    if configuration.autoExecuteTools {
                        var askUserCall: ToolCall?
                        var askUserQuestion: String?
                        var regularCalls: [ToolCall] = []

                        for call in toolCalls {
                            continuation.yield(.running(step: .toolCall(call)))
                            if call.name == "ask_user" {
                                let question = extractQuestion(from: call)
                                askUserCall = call
                                askUserQuestion = question
                                continuation.yield(.running(step: .askingUser(question)))
                            } else {
                                regularCalls.append(call)
                            }
                        }

                        // 通常ツールを実行
                        let toolResults: [ToolResponse]
                        if regularCalls.count <= 1 {
                            var results: [ToolResponse] = []
                            for call in regularCalls {
                                let result = await executeToolSafely(call, tools: tools)
                                try Task.checkCancellation()
                                results.append(result)
                                continuation.yield(.running(step: .toolResult(result)))
                            }
                            toolResults = results
                        } else {
                            let toolSet = tools
                            toolResults = await withTaskGroup(of: (Int, ToolResponse).self) { group in
                                for (index, call) in regularCalls.enumerated() {
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
                                    continuation.yield(.running(step: .toolResult(pair.1)))
                                    indexed.append(pair)
                                }
                                return indexed.sorted(by: { $0.0 < $1.0 }).map(\.1)
                            }
                        }

                        if !toolResults.isEmpty {
                            addToolResults(toolResults)
                        }

                        // ask_user 処理
                        if let call = askUserCall, let question = askUserQuestion {
                            askUserCallCount += 1

                            if let maxCalls = configuration.maxAskUserCalls, askUserCallCount > maxCalls {
                                let syntheticAnswer = "Proceed with your best judgment."
                                let result = ToolResponse(
                                    callId: call.id, name: call.name,
                                    output: syntheticAnswer, isError: false
                                )
                                addToolResults([result])
                                continuation.yield(.running(step: .toolResult(result)))
                                pendingAskUserCall = nil
                            } else {
                                pendingAskUserCall = call
                                status = .awaitingUserInput(question: question)
                                continuation.yield(.awaitingUserInput(question: question))

                                let answer = await withCheckedContinuation { cont in
                                    self.answerContinuation = cont
                                }

                                guard status != .paused else {
                                    continuation.yield(.paused)
                                    continuation.finish()
                                    return
                                }

                                status = .running
                                continuation.yield(.running(step: .userMessage(answer)))

                                let result = ToolResponse(
                                    callId: call.id, name: call.name,
                                    output: answer.isEmpty ? "No answer provided" : answer,
                                    isError: false
                                )
                                addToolResults([result])
                                continuation.yield(.running(step: .toolResult(result)))
                                pendingAskUserCall = nil
                            }
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
            if !lastText.isEmpty,
               let output = try? JSONDecoder.snakeCaseDecoder.decode(Output.self, from: Data(lastText.utf8)) {
                status = .idle
                continuation.yield(.completed(output: output))
                continuation.finish()
            } else {
                let error = ConversationalAgentError.maxStepsExceeded(steps: maxSteps)
                status = .failed(error: error.localizedDescription)
                continuation.yield(.failed(error: error.localizedDescription))
                continuation.finish(throwing: error)
            }

        } catch is CancellationError {
            status = .paused
            continuation.yield(.paused)
            continuation.finish()
        } catch let error as ConversationalAgentError {
            status = .failed(error: error.localizedDescription)
            continuation.yield(.failed(error: error.localizedDescription))
            continuation.finish(throwing: error)
        } catch {
            let wrappedError = ConversationalAgentError.invalidState(error.localizedDescription)
            status = .failed(error: wrappedError.localizedDescription)
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

    private func addToolResults(_ results: [ToolResponse]) {
        guard !results.isEmpty else { return }

        let contents = results.map { result in
            LLMMessage.MessageContent.toolResult(
                toolCallId: result.callId,
                name: result.name,
                content: result.output,
                isError: result.isError
            )
        }
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

    private func extractQuestion(from call: ToolCall) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any],
           let question = dict["question"] as? String {
            return question
        }
        return "Please provide additional information."
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
