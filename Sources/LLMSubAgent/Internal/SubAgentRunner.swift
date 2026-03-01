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
        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps
        let deadline = timeout.map { ContinuousClock.now + $0 }

        while step < maxSteps {
            try checkForCancellation(messages: messages)
            step += 1

            // ソフトリミット注入
            if step == softMaxSteps {
                let softLimitMsg =
                    "IMPORTANT: You are running low on remaining steps (\(maxSteps - step) left). "
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
                        maxTokens: nil
                    )
                    }
                )
            } catch let error as LLMError {
                throw SubAgentError.llmError(error)
            }

            try checkForCancellation(messages: messages)
            appendAssistantResponse(response, to: &messages)

            // ツール呼び出しの抽出
            let toolCalls = extractToolCalls(from: response)

            if toolCalls.isEmpty {
                // ツール呼び出しなし → テキストで完了
                let text = extractTextContent(from: response)
                if text.isEmpty {
                    throw SubAgentError.emptyResponse
                }
                await eventHandler?(.completed(taskId: taskId, result: text))
                return SubAgentRunResult(output: text, messages: messages)
            }

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
                            output: toolResult.stringValue,
                            isError: toolResult.isError
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
                )
                try checkForCancellation(messages: messages)
                toolResults.append(result)
                await eventHandler?(.toolResult(taskId: taskId, result))
            }

            if !toolResults.isEmpty {
                appendToolResults(toolResults, to: &messages)
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
                content: result.output,
                isError: result.isError
            )
        }
        messages.append(LLMMessage(role: .user, contents: contents))
    }

    private static func extractToolCalls(from response: LLMResponse) -> [ToolCall] {
        response.content.compactMap { block in
            guard case .toolUse(let id, let name, let input) = block else {
                return nil
            }
            return ToolCall(id: id, name: name, arguments: input)
        }
    }

    private static func extractTextContent(from response: LLMResponse) -> String {
        response.content.compactMap { block -> String? in
            if case .text(let value) = block { return value }
            return nil
        }.joined()
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
