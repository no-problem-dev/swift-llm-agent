import Foundation
import LLMClient
import LLMTool
import LLMAgent

package struct SubAgentRunResult: Sendable {
    package let output: String
    package let messages: [LLMMessage]
}

package enum SubAgentRunInterruption: Error, Sendable {
    case timedOut(messages: [LLMMessage])
    case stepLimitExceeded(messages: [LLMMessage])
    case cancelled(messages: [LLMMessage])

    package var messages: [LLMMessage] {
        switch self {
        case .timedOut(let messages), .stepLimitExceeded(let messages), .cancelled(let messages):
            messages
        }
    }
}

// MARK: - SubAgentRunner

/// サブエージェント実行エンジン
///
/// `PlainTextAgentSession.runAgentLoop()` の簡略版。
/// ask_user サポートなし（完全自律）、ストリーミングなし。
package enum SubAgentRunner {

    /// サブエージェントを実行し、最終テキストを返す
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - model: 使用するモデル
    ///   - prompt: ユーザープロンプト
    ///   - tools: 使用可能なツール
    ///   - systemPrompt: システムプロンプト（オプション）
    ///   - configuration: エージェント設定
    ///   - timeout: タイムアウト（オプション）
    ///   - taskId: タスク識別子（並列実行時のイベント識別用）
    ///   - eventHandler: イベントハンドラー（オプション）
    /// - Returns: エージェントの最終テキスト応答
    package static func run<Client: AgentCapableClient>(
        client: Client,
        model: Client.Model,
        messages: [LLMMessage],
        tools: ToolSet,
        systemPrompt: SystemPrompt?,
        configuration: AgentConfiguration,
        timeout: Duration?,
        taskId: UUID,
        eventHandler: SubAgentEventHandler?
    ) async throws -> SubAgentRunResult where Client.Model: Sendable {
        try await executeLoop(
            client: client,
            model: model,
            initialMessages: messages,
            tools: tools,
            systemPrompt: systemPrompt,
            configuration: configuration,
            timeout: timeout,
            taskId: taskId,
            eventHandler: eventHandler
        )
    }

    // MARK: - Private

    private static func executeLoop<Client: AgentCapableClient>(
        client: Client,
        model: Client.Model,
        initialMessages: [LLMMessage],
        tools: ToolSet,
        systemPrompt: SystemPrompt?,
        configuration: AgentConfiguration,
        timeout: Duration?,
        taskId: UUID,
        eventHandler: SubAgentEventHandler?
    ) async throws -> SubAgentRunResult where Client.Model: Sendable {
        var messages = initialMessages
        let stateManager = AgentLoopStateManager(configuration: configuration)

        // サブエージェントではステップ上限が主な制約のため、
        // maxToolCallsPerTool をステップ数に合わせてスケーリング
        // （例: maxSteps=20, maxToolCallsPerTool=5 → 20 にスケール）
        let scaledConfiguration = AgentConfiguration(
            maxSteps: configuration.maxSteps,
            softMaxSteps: configuration.softMaxSteps,
            autoExecuteTools: configuration.autoExecuteTools,
            maxDuplicateToolCalls: configuration.maxDuplicateToolCalls,
            maxToolCallsPerTool: configuration.maxToolCallsPerTool.map {
                max($0, configuration.maxSteps)
            },
            maxInteractiveCalls: configuration.maxInteractiveCalls,
            thinkingMode: configuration.thinkingMode,
            skipFinalOutput: configuration.skipFinalOutput
        )
        let policy = TerminationPolicyFactory.make(from: scaledConfiguration)
        let deadline = timeout.map { ContinuousClock.now + $0 }

        while await !stateManager.isAtStepLimit {
            try checkForCancellation(messages: messages)
            try await stateManager.incrementStep()

            // ソフトリミット注入
            if await stateManager.isAtSoftLimit {
                let maxSteps = await stateManager.maxSteps
                let currentStep = await stateManager.currentStep
                let softLimitMsg =
                    "IMPORTANT: You are running low on remaining steps (\(maxSteps - currentStep) left). "
                    + "Wrap up your current work and provide your final answer now. "
                    + "Do not start new tool calls unless absolutely necessary."
                messages.append(LLMMessage.user(softLimitMsg))
            }

            // 孤立ツール呼び出し修復
            messages.sanitizeOrphanedToolUses()

            // LLM 呼び出し
            let response: LLMResponse
            let requestMessages = messages
            do {
                response = try await runWithinDeadline(
                    deadline: deadline,
                    messages: requestMessages,
                    operation: {
                    try await client.executeAgentStep(
                        messages: requestMessages,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        toolChoice: tools.isEmpty ? nil : .auto,
                        responseSchema: nil,
                        thinkingMode: configuration.thinkingMode,
                        reasoningEffort: configuration.reasoningEffort,
                        maxTokens: configuration.maxTokens,
                    cachePolicy: .implicit
                    )
                    }
                )
            } catch let error as LLMError {
                throw SubAgentError.llmError(error)
            }

            try checkForCancellation(messages: messages)
            appendAssistantResponse(response, to: &messages)

            // TerminationPolicy による判定
            let decision = await policy.shouldTerminate(
                response: response,
                context: stateManager
            )

            switch decision {
            case .continueWithTools(let toolCalls):
                // ツール呼び出し履歴を記録
                await stateManager.recordToolCalls(toolCalls)

                // ツール実行は逐次に限定し、各呼び出しでチェックポイントを残す
                var toolResults: [ToolResponse] = []
                for call in toolCalls {
                    await eventHandler?(.toolCall(taskId: taskId, call))
                    let checkpointMessages = messages
                    let result = try await runWithinDeadline(
                        deadline: deadline,
                        messages: checkpointMessages,
                        operation: {
                        do {
                            let toolResult = try await tools.execute(toolNamed: call.name, with: call.arguments)
                            return ToolResponse(
                                callId: call.id,
                                name: call.name,
                                content: .success( toolResult.stringValue)
                            )
                        } catch {
                            return ToolResponse(
                                callId: call.id,
                                name: call.name,
                                content: .failure( "Error: \(error.localizedDescription)")
                            )
                        }
                        }
                    )
                    try checkForCancellation(messages: messages)
                    toolResults.append(result)
                    await eventHandler?(.toolResult(taskId: taskId, result))
                }

                if !toolResults.isEmpty {
                    appendToolResults(toolResults, to: &messages)
                }

            case .continueWithThinking:
                continue

            case .terminateWithOutput(let text):
                if text.isEmpty {
                    throw SubAgentError.emptyResponse
                }
                await eventHandler?(.completed(taskId: taskId, result: text))
                return SubAgentRunResult(output: text, messages: messages)

            case .terminateImmediately(let reason):
                // 早期終了: 最後のテキストで完了を試行
                let lastText = extractLastAssistantText(from: messages)
                if !lastText.isEmpty {
                    #if DEBUG
                    switch reason {
                    case .duplicateToolCallDetected(let toolName, let count):
                        print("[SubAgent] Duplicate tool call detected: \(toolName) called \(count) times with same input")
                    case .maxToolCallsPerToolReached(let toolName, let count):
                        print("[SubAgent] Tool call limit reached: \(toolName) called \(count) times total")
                    default:
                        break
                    }
                    #endif
                    await eventHandler?(.completed(taskId: taskId, result: lastText))
                    return SubAgentRunResult(output: lastText, messages: messages)
                }
                throw SubAgentRunInterruption.stepLimitExceeded(messages: messages)
            }
        }

        // ハードリミット到達: 最後のテキストで完了を試行
        let lastText = extractLastAssistantText(from: messages)
        if !lastText.isEmpty {
            await eventHandler?(.completed(taskId: taskId, result: lastText))
            return SubAgentRunResult(output: lastText, messages: messages)
        }

        throw SubAgentRunInterruption.stepLimitExceeded(messages: messages)
    }

    // MARK: - Message Helpers

    private static func appendAssistantResponse(_ response: LLMResponse, to messages: inout [LLMMessage]) {
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

    private static func appendToolResults(_ results: [ToolResponse], to messages: inout [LLMMessage]) {
        guard !results.isEmpty else { return }

        let contents = results.map { result in
            LLMMessage.MessageContent.toolResult(
                toolCallId: result.callId,
                name: result.name,
                content: result.content
            )
        }
        messages.append(LLMMessage(role: .user, contents: contents))
    }

    private static func extractLastAssistantText(from messages: [LLMMessage]) -> String {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else {
            return ""
        }
        return lastAssistant.contents.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()
    }

    private static func runWithinDeadline<T: Sendable>(
        deadline: ContinuousClock.Instant?,
        messages: [LLMMessage],
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        guard let deadline else {
            return try await operation()
        }

        let remaining = deadline - ContinuousClock.now
        if remaining <= .zero {
            throw SubAgentRunInterruption.timedOut(messages: messages)
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: remaining)
                throw SubAgentRunInterruption.timedOut(messages: messages)
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private static func checkForCancellation(messages: [LLMMessage]) throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw SubAgentRunInterruption.cancelled(messages: messages)
        }
    }
}
