import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - PlainTextAgentSession

/// ツール実行ループを持つが、構造化出力フェーズをスキップするエージェントセッション
///
/// `ConversationalAgentSession` と同じツール実行ループを持ちますが、
/// finalOutput フェーズ（構造化 JSON 出力）を省略し、
/// LLM のテキスト応答をそのまま返します。
///
/// ローカル LLM など、ツール呼び出しは可能だが構造化 JSON 出力が安定しない
/// モデルに適しています。
///
/// ## ConversationalAgentSession との違い
///
/// | 項目 | ConversationalAgentSession | PlainTextAgentSession |
/// |---|---|---|
/// | LoopPhase | `.toolUse` / `.finalOutput` | `.toolUse` のみ |
/// | ツールなし応答 | `.finalOutput` へ遷移 | テキストで `.completed` |
/// | 完了時の型 | `Output: StructuredProtocol` | `String` |
///
/// ## 使用例
///
/// ```swift
/// let session = PlainTextAgentSession(
///     client: localClient,
///     systemPrompt: SystemPrompt { "アシスタントです。" },
///     tools: ToolSet {
///         CalculatorTool()
///     }
/// )
///
/// for try await phase in session.run(input: "2+3を計算して", model: modelSpec) {
///     switch phase {
///     case .running(let step):
///         print("Step: \(step)")
///     case .completed(let text):
///         print("Result: \(text)")
///     default:
///         break
///     }
/// }
/// ```
public actor PlainTextAgentSession<Client: AgentCapableClient>
    where Client.Model: Sendable
{
    // MARK: - Properties

    private let client: Client
    private var messages: [LLMMessage] = []
    private let systemPrompt: SystemPrompt?
    private let tools: ToolSet
    private let configuration: AgentConfiguration
    private var interruptQueue: [String] = []

    /// 現在のセッション状態（型パラメータなし）
    public private(set) var status: SessionStatus = .idle

    /// 保留中の ask_user ツール呼び出し
    private var pendingAskUserCall: ToolCall?

    /// ユーザー回答待ちの CheckedContinuation
    private var answerContinuation: CheckedContinuation<String, Never>?

    /// ask_user ツールの呼び出しカウント
    private var askUserCallCount: Int = 0

    // MARK: - Initialization

    /// プレーンテキストエージェントセッションを初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - systemPrompt: システムプロンプト（オプション）
    ///   - tools: 使用するツールセット
    ///   - interactiveMode: 対話モードを有効にするか（デフォルト: false）
    ///   - configuration: エージェント設定（オプション）
    ///   - initialMessages: 復元する会話履歴（オプション）
    public init(
        client: Client,
        systemPrompt: SystemPrompt? = nil,
        tools: ToolSet,
        interactiveMode: Bool = false,
        configuration: AgentConfiguration = .default,
        initialMessages: [LLMMessage] = []
    ) {
        self.client = client
        self.systemPrompt = systemPrompt
        self.tools = interactiveMode ? tools.appending(AskUserTool()) : tools
        self.configuration = configuration
        self.messages = initialMessages
    }

    // MARK: - Public API

    /// セッションが実行中かどうか
    public var running: Bool {
        status.isActive
    }

    /// 会話のターン数
    public var turnCount: Int {
        messages.filter { $0.role == .user }.count
    }

    /// エージェントループを実行
    nonisolated public func run(
        input: LLMInput,
        model: Client.Model
    ) -> AsyncThrowingStream<PlainTextSessionPhase, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeLoop(
                    input: input,
                    model: model,
                    continuation: continuation
                )
            }
        }
    }

    /// 一時停止状態から再開
    nonisolated public func resume(
        model: Client.Model
    ) -> AsyncThrowingStream<PlainTextSessionPhase, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeResumeLoop(
                    model: model,
                    continuation: continuation
                )
            }
        }
    }

    /// ユーザーの回答を送信（ask_user 応答）
    public func reply(_ answer: String) {
        guard status.canReply, let continuation = answerContinuation else { return }
        answerContinuation = nil
        continuation.resume(returning: answer)
    }

    /// 割り込みメッセージを追加
    public func interrupt(_ message: String) {
        guard status.canInterrupt else { return }
        interruptQueue.append(message)
    }

    /// セッションをキャンセル
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

    /// セッションをクリア
    public func clear() {
        guard status.canClear else { return }
        messages.removeAll()
        interruptQueue.removeAll()
        status = .idle
    }

    /// メッセージ履歴を取得
    public func getMessages() -> [LLMMessage] {
        messages
    }

    // MARK: - Internal Loop

    private func executeLoop(
        input: LLMInput,
        model: Client.Model,
        continuation: AsyncThrowingStream<PlainTextSessionPhase, Error>.Continuation
    ) async {
        guard status.canRun else {
            continuation.finish(throwing: ConversationalAgentError.sessionAlreadyRunning)
            return
        }

        messages.append(input.toLLMMessage())
        let userMessageText = input.prompt.render()
        status = .running
        continuation.yield(.running(step: .userMessage(userMessageText)))

        await runAgentLoop(model: model, continuation: continuation)
    }

    private func executeResumeLoop(
        model: Client.Model,
        continuation: AsyncThrowingStream<PlainTextSessionPhase, Error>.Continuation
    ) async {
        guard status.canResume else {
            continuation.finish(throwing: ConversationalAgentError.sessionAlreadyRunning)
            return
        }

        guard !messages.isEmpty else {
            let error = ConversationalAgentError.invalidState(
                "No conversation history to resume. Use run() instead."
            )
            continuation.finish(throwing: error)
            return
        }

        repairIncompleteToolUses()

        let continueMsg = "Please continue where you left off."
        messages.append(LLMMessage.user(continueMsg))
        status = .running
        continuation.yield(.running(step: .userMessage(continueMsg)))

        await runAgentLoop(model: model, continuation: continuation)
    }

    /// 不完全な tool_use を検出して修復
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

    // MARK: - Agent Loop

    private func runAgentLoop(
        model: Client.Model,
        continuation: AsyncThrowingStream<PlainTextSessionPhase, Error>.Continuation
    ) async {
        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps

        do {
            while step < maxSteps {
                try Task.checkCancellation()
                step += 1

                // ソフトリミット注入
                if step == softMaxSteps {
                    let softLimitMsg =
                        "IMPORTANT: You are running low on remaining steps (\(maxSteps - step) left). "
                        + "Wrap up your current work and provide your final answer now. "
                        + "Do not start new tool calls unless absolutely necessary."
                    messages.append(LLMMessage.user(softLimitMsg))
                    continuation.yield(.running(step: .interrupted(softLimitMsg)))
                }

                // 割り込みチェックポイント
                if !interruptQueue.isEmpty {
                    for interruptMsg in interruptQueue {
                        messages.append(LLMMessage.user(interruptMsg))
                        continuation.yield(.running(step: .interrupted(interruptMsg)))
                    }
                    interruptQueue.removeAll()
                }

                // LLM 呼び出し（toolUse フェーズのみ）
                continuation.yield(.running(step: .thinking))

                // クラッシュ等で tool_result が欠落した場合に備えてメッセージ履歴を修復
                messages.sanitizeOrphanedToolUses()

                let response: LLMResponse
                do {
                    response = try await client.executeAgentStep(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        toolChoice: tools.isEmpty ? nil : .auto,
                        responseSchema: nil,
                        maxTokens: nil
                    )
                } catch let error as LLMError {
                    throw ConversationalAgentError.llmError(error)
                }

                try Task.checkCancellation()
                addAssistantResponse(response)

                // ツール呼び出しの抽出
                let toolCalls = extractToolCalls(from: response)

                if toolCalls.isEmpty {
                    // ツール呼び出しなし → テキストで完了
                    let text = extractTextContent(from: response)
                    status = .idle
                    continuation.yield(.completed(text: text))
                    continuation.finish()
                    return
                }

                // ツール実行
                if configuration.autoExecuteTools {
                    var askUserCall: ToolCall?
                    var askUserQuestion: String?
                    var regularCalls: [ToolCall] = []

                    // Phase 1: イベント発火 + ask_user 分離
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

                    // Phase 2: 通常ツールを並列実行
                    let toolResults: [ToolResponse]
                    if regularCalls.count <= 1 {
                        var results: [ToolResponse] = []
                        for call in regularCalls {
                            let result = await executeToolSafely(call)
                            try Task.checkCancellation()
                            results.append(result)
                            continuation.yield(.running(step: .toolResult(result)))
                        }
                        toolResults = results
                    } else {
                        let toolSet = self.tools
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

                        if let maxCalls = configuration.maxAskUserCalls,
                            askUserCallCount > maxCalls
                        {
                            let syntheticAnswer = "Proceed with your best judgment."
                            let result = ToolResponse(
                                callId: call.id,
                                name: call.name,
                                output: syntheticAnswer,
                                isError: false
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
                                callId: call.id,
                                name: call.name,
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
            }

            // ハードリミット到達: 最後のテキストで完了
            let lastText = extractLastAssistantText()
            if !lastText.isEmpty {
                status = .idle
                continuation.yield(.completed(text: lastText))
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

    private func executeToolSafely(_ call: ToolCall) async -> ToolResponse {
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

    private func extractTextContent(from response: LLMResponse) -> String {
        response.content.compactMap { block -> String? in
            if case .text(let value) = block { return value }
            return nil
        }.joined()
    }

    private func extractQuestion(from call: ToolCall) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any],
            let question = dict["question"] as? String
        {
            return question
        }
        return "Please provide additional information."
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

