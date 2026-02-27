import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - LoopPhase

/// エージェントループの内部フェーズ
///
/// LLMの応答に基づいて次の処理を決定するための内部フェーズです。
/// `SessionStatus`（セッション全体のライフサイクル）とは異なり、
/// これはループ内でLLMがどのような出力を返すかを管理します。
private enum LoopPhase: Sendable {
    /// ツール使用フェーズ
    ///
    /// LLM はツールを呼び出すか、テキスト応答を返すことができます。
    case toolUse

    /// 最終出力フェーズ
    ///
    /// ツール呼び出しが完了し、構造化出力を要求するフェーズです。
    /// リトライ回数を追跡します。
    case finalOutput(retryCount: Int)
}

// MARK: - FinalOutputConstants

/// 最終出力フェーズの定数
private enum FinalOutputConstants {
    /// 最終出力デコードの最大リトライ回数
    static let maxDecodeRetries: Int = 2

    /// 最終出力要求メッセージ
    ///
    /// 構造化出力を要求するためのユーザーメッセージです。
    static let requestMessage = "Please provide your final response in the required JSON format."
}

// MARK: - ConversationalAgentSession

/// `ConversationalAgentSessionProtocol` の標準実装
///
/// Actor として実装され、スレッドセーフな会話型エージェントセッションを提供します。
///
/// ## 状態管理
///
/// - `status`: 型パラメータなしの内部状態（`SessionStatus`）
/// - `run()` の戻り値: 型付きのストリーム（`AsyncThrowingStream<SessionPhase<Output>, Error>`）
///
/// ## 使用例
///
/// ```swift
/// let session = ConversationalAgentSession(
///     client: AnthropicClient(apiKey: "..."),
///     systemPrompt: SystemPrompt { "あなたはリサーチアシスタントです。" },
///     tools: ToolSet {
///         WebSearchTool()
///     }
/// )
///
/// // 状態確認
/// if await session.status.canRun {
///     // ストリームで型付き結果を取得
///     for try await phase in session.run("調査して", model: .sonnet, outputType: ResearchResult.self) {
///         switch phase {
///         case .running(let step):
///             print("Step: \(step)")
///         case .completed(let output):
///             print("Result: \(output.summary)")
///         default:
///             break
///         }
///     }
/// }
/// ```
public actor ConversationalAgentSession<Client: AgentCapableClient>: ConversationalAgentSessionProtocol
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
    ///
    /// `ask_user` ツール呼び出し時に設定され、`reply(_:)` で再開されます。
    private var answerContinuation: CheckedContinuation<String, Never>?

    /// ask_user ツールの呼び出しカウント
    private var askUserCallCount: Int = 0

    // MARK: - Initialization

    /// 会話エージェントセッションを初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - systemPrompt: システムプロンプト（オプション）
    ///   - tools: 使用するツールセット
    ///   - interactiveMode: 対話モードを有効にするか（デフォルト: false）
    ///     `true` の場合、AI がユーザーに質問できるようになります。
    ///   - configuration: エージェント設定（オプション）
    ///   - initialMessages: 復元する会話履歴（オプション）
    ///     過去のセッションを復元する場合に使用します。
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
        // 対話モードの場合は ask_user ツールを自動追加
        self.tools = interactiveMode ? tools.appending(AskUserTool()) : tools
        self.configuration = configuration
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

        // キャンセル時は空文字列で再開（ループ内でエラーハンドリング）
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
        // 回答待ち状態でない場合は何もしない
        guard status.canReply, let continuation = answerContinuation else { return }
        answerContinuation = nil
        continuation.resume(returning: answer)
    }

    // MARK: - Protocol Conformance: Core API

    nonisolated public func run<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        outputType: Output.Type = Output.self
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeLoop(
                    input: input,
                    model: model,
                    outputType: Output.self,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Resume API

    nonisolated public func resume<Output: StructuredProtocol>(
        model: Client.Model,
        outputType: Output.Type
    ) -> AsyncThrowingStream<SessionPhase<Output>, Error> {
        makeCancellableStream { continuation in
            Task {
                await self.executeResumeLoop(
                    model: model,
                    outputType: Output.self,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Internal Loop

    private func executeResumeLoop<Output: StructuredProtocol>(
        model: Client.Model,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        guard status.canResume else {
            let error = ConversationalAgentError.sessionAlreadyRunning
            continuation.finish(throwing: error)
            return
        }

        // 会話履歴がない場合はエラー
        guard !messages.isEmpty else {
            let error = ConversationalAgentError.invalidState("No conversation history to resume. Use run() instead.")
            continuation.finish(throwing: error)
            return
        }

        // 不完全な tool_use を修復
        repairIncompleteToolUses()

        // 継続メッセージを追加
        let continueMsg = "Please continue where you left off."
        messages.append(LLMMessage.user(continueMsg))

        // userMessage ステップを発行
        status = .running
        continuation.yield(.running(step: .userMessage(continueMsg)))

        await runAgentLoop(
            model: model,
            outputType: Output.self,
            continuation: continuation
        )
    }

    private func executeLoop<Output: StructuredProtocol>(
        input: LLMInput,
        model: Client.Model,
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        guard status.canRun else {
            let error = ConversationalAgentError.sessionAlreadyRunning
            continuation.finish(throwing: error)
            return
        }

        // ユーザーメッセージを追加
        messages.append(input.toLLMMessage())

        // userMessage ステップを発行
        let userMessageText = input.prompt.render()
        status = .running
        continuation.yield(.running(step: .userMessage(userMessageText)))

        await runAgentLoop(
            model: model,
            outputType: Output.self,
            continuation: continuation
        )
    }

    /// 不完全な tool_use を検出して修復
    ///
    /// アシスタントメッセージの tool_use に対応する tool_result がない場合、
    /// ダミーの tool_result を追加してセッションを継続可能にします。
    private func repairIncompleteToolUses() {
        // 最後のアシスタントメッセージから tool_use を抽出
        var pendingToolUseIds: [(id: String, name: String)] = []

        for message in messages {
            if message.role == .assistant {
                // tool_use を収集
                for content in message.contents {
                    if case .toolUse(let id, let name, _) = content {
                        pendingToolUseIds.append((id: id, name: name))
                    }
                }
            } else if message.role == .user {
                // tool_result で解決
                for content in message.contents {
                    if case .toolResult(let toolCallId, _, _, _) = content {
                        pendingToolUseIds.removeAll { $0.id == toolCallId }
                    }
                }
            }
        }

        // 未解決の tool_use があれば、ダミーの tool_result を追加
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
        outputType: Output.Type,
        continuation: AsyncThrowingStream<SessionPhase<Output>, Error>.Continuation
    ) async {
        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps
        var loopPhase: LoopPhase = .toolUse

        do {
            while step < maxSteps {
                try Task.checkCancellation()
                step += 1

                // ソフトリミット注入: まとめを促すメッセージを会話履歴に追加
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

                // LoopPhaseに応じて LLM 呼び出し
                continuation.yield(.running(step: .thinking))

                // クラッシュ等で tool_result が欠落した場合に備えてメッセージ履歴を修復
                messages.sanitizeOrphanedToolUses()

                let response: LLMResponse
                do {
                    switch loopPhase {
                    case .toolUse:
                        // ツール使用フェーズ: ツール有効、構造化出力なし（ストリーミング）
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
                        // 最終出力フェーズ: ツール無効、構造化出力要求（ストリーミング）
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

                // LoopPhaseに応じた処理
                switch loopPhase {
                case .toolUse:
                    let toolCalls = extractToolCalls(from: response)

                    if toolCalls.isEmpty {
                        // ツール呼び出しがない → 最終出力フェーズへ移行
                        if !tools.isEmpty {
                            // ツールがある場合は finalOutput フェーズへ移行
                            loopPhase = .finalOutput(retryCount: 0)
                            addFinalOutputRequest()
                            // ループ継続（次のイテレーションで finalOutput フェーズの処理）
                            continue
                        } else {
                            // ツールがない場合は直接デコードを試行
                            if let output = try? decodeOutput(response, as: Output.self) {
                                status = .idle
                                continuation.yield(.completed(output: output))
                                continuation.finish()
                                return
                            } else {
                                // デコード失敗時はエラー
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
                            // 1件以下は逐次（TaskGroup オーバーヘッド回避）
                            var results: [ToolResponse] = []
                            for call in regularCalls {
                                let result = await executeToolSafely(call)
                                try Task.checkCancellation()
                                results.append(result)
                                continuation.yield(.running(step: .toolResult(result)))
                            }
                            toolResults = results
                        } else {
                            // 2件以上は並列実行
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

                        // ツール結果を追加
                        if !toolResults.isEmpty {
                            addToolResults(toolResults)
                        }

                        // ask_user が呼ばれた場合
                        if let call = askUserCall, let question = askUserQuestion {
                            askUserCallCount += 1

                            // ask_user バジェット制御
                            if let maxCalls = configuration.maxAskUserCalls, askUserCallCount > maxCalls {
                                // バジェット超過: ユーザーを待たず synthetic 回答を返す
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
                                // 通常の ask_user フロー
                                pendingAskUserCall = call
                                status = .awaitingUserInput(question: question)
                                continuation.yield(.awaitingUserInput(question: question))

                                // withCheckedContinuation で一時停止
                                let answer = await withCheckedContinuation { cont in
                                    self.answerContinuation = cont
                                }

                                // キャンセルされた場合（paused状態）は終了
                                guard status != .paused else {
                                    // cancel() で paused に変更されている場合
                                    continuation.yield(.paused)
                                    continuation.finish()
                                    return
                                }

                                // running に戻る
                                status = .running
                                continuation.yield(.running(step: .userMessage(answer)))

                                // ツール結果として回答を追加
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
                            // ループ継続（次のイテレーションで LLM に回答を渡す）
                        }
                    } else {
                        continuation.finish()
                        return
                    }

                case .finalOutput(let retryCount):
                    // 構造化出力のデコードを試行
                    do {
                        let output = try decodeOutput(response, as: Output.self)
                        status = .idle
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    } catch {
                        // デコード失敗 → リトライ
                        let newRetryCount = retryCount + 1
                        if newRetryCount >= FinalOutputConstants.maxDecodeRetries {
                            throw ConversationalAgentError.outputDecodingFailed(error)
                        }
                        loopPhase = .finalOutput(retryCount: newRetryCount)
                        addFinalOutputRequest()
                        // ループ継続（リトライ）
                        continue
                    }
                }
            }

            // ハードリミット到達: graceful degradation
            // 最後の assistant メッセージからテキストを抽出してデコードを試行
            let lastText = extractLastAssistantText()
            if !lastText.isEmpty,
               let output = try? JSONDecoder.snakeCaseDecoder.decode(Output.self, from: Data(lastText.utf8)) {
                // 部分結果でも構造化出力としてデコードできた場合は completed として返す
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
                // 生成されたメディアは会話履歴には含めない
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

    private func decodeOutput<Output: StructuredProtocol>(
        _ response: LLMResponse,
        as type: Output.Type
    ) throws -> Output {
        let text = extractTextContent(from: response)
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

    /// ask_user ツールの引数から質問文を抽出
    private func extractQuestion(from call: ToolCall) -> String {
        // JSON から question フィールドを抽出
        if let dict = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any],
           let question = dict["question"] as? String {
            return question
        }
        return "Please provide additional information."
    }

    // MARK: - Final Output Helpers

    /// 最終出力要求メッセージを追加
    private func addFinalOutputRequest() {
        let message = LLMMessage.user(FinalOutputConstants.requestMessage)
        messages.append(message)
    }

    /// 最後の assistant メッセージからテキストコンテンツを抽出
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

