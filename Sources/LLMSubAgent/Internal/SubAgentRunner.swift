import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - SubAgentRunner

/// サブエージェント実行エンジン
///
/// `PlainTextAgentSession.runAgentLoop()` の簡略版。
/// ask_user サポートなし（完全自律）、ストリーミングなし。
internal enum SubAgentRunner {

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
    static func run<Client: AgentCapableClient>(
        client: Client,
        model: Client.Model,
        prompt: String,
        tools: ToolSet,
        systemPrompt: Prompt?,
        configuration: AgentConfiguration,
        timeout: Duration?,
        taskId: UUID,
        eventHandler: SubAgentEventHandler?
    ) async throws -> String where Client.Model: Sendable {
        if let timeout {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await executeLoop(
                        client: client,
                        model: model,
                        prompt: prompt,
                        tools: tools,
                        systemPrompt: systemPrompt,
                        configuration: configuration,
                        taskId: taskId,
                        eventHandler: eventHandler
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw SubAgentError.timeout(timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } else {
            return try await executeLoop(
                client: client,
                model: model,
                prompt: prompt,
                tools: tools,
                systemPrompt: systemPrompt,
                configuration: configuration,
                taskId: taskId,
                eventHandler: eventHandler
            )
        }
    }

    // MARK: - Private

    private static func executeLoop<Client: AgentCapableClient>(
        client: Client,
        model: Client.Model,
        prompt: String,
        tools: ToolSet,
        systemPrompt: Prompt?,
        configuration: AgentConfiguration,
        taskId: UUID,
        eventHandler: SubAgentEventHandler?
    ) async throws -> String where Client.Model: Sendable {
        var messages: [LLMMessage] = [LLMMessage.user(prompt)]
        var step = 0
        let maxSteps = configuration.maxSteps
        let softMaxSteps = configuration.softMaxSteps

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
            }

            // 孤立ツール呼び出し修復
            messages.sanitizeOrphanedToolUses()

            // LLM 呼び出し
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
                throw SubAgentError.llmError(error)
            }

            try Task.checkCancellation()
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
                return text
            }

            // ツール実行（2件以上は並列）
            let toolResults: [ToolResponse]
            if toolCalls.count <= 1 {
                var results: [ToolResponse] = []
                for call in toolCalls {
                    await eventHandler?(.toolCall(taskId: taskId, call))
                    let result = await executeToolSafely(call, tools: tools)
                    try Task.checkCancellation()
                    results.append(result)
                    await eventHandler?(.toolResult(taskId: taskId, result))
                }
                toolResults = results
            } else {
                // 全ツールコールイベントを先行発火
                for call in toolCalls {
                    await eventHandler?(.toolCall(taskId: taskId, call))
                }
                // 並列実行
                let capturedTools = tools
                toolResults = await withTaskGroup(of: (Int, ToolResponse).self) { group in
                    for (index, call) in toolCalls.enumerated() {
                        group.addTask {
                            let result = await executeToolSafely(call, tools: capturedTools)
                            return (index, result)
                        }
                    }
                    var indexed: [(Int, ToolResponse)] = []
                    for await pair in group {
                        await eventHandler?(.toolResult(taskId: taskId, pair.1))
                        indexed.append(pair)
                    }
                    return indexed.sorted(by: { $0.0 < $1.0 }).map(\.1)
                }
            }

            if !toolResults.isEmpty {
                appendToolResults(toolResults, to: &messages)
            }
        }

        // ハードリミット到達: 最後のテキストで完了を試行
        let lastText = extractLastAssistantText(from: messages)
        if !lastText.isEmpty {
            await eventHandler?(.completed(taskId: taskId, result: lastText))
            return lastText
        }

        throw SubAgentError.maxStepsExceeded(steps: maxSteps)
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

    private static func executeToolSafely(_ call: ToolCall, tools: ToolSet) async -> ToolResponse {
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
}
