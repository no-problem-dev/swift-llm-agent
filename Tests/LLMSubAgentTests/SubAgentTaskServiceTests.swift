import Testing
import Foundation
@testable import LLMSubAgent
import LLMClient
import LLMTool
import LLMAgent

@Test func testBackgroundTaskCompletes() async {
    let service = SubAgentTaskService(client: FastMockClient())

    let info = await service.startTask(
        agentType: "researcher",
        description: "Research task",
        prompt: "Research AI trends",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .seconds(5),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    let finalInfo = await service.waitForTask(id: info.id, timeout: .seconds(1))
    guard case .completed(let result) = finalInfo?.status else {
        Issue.record("Expected completed task but got \(String(describing: finalInfo?.status))")
        return
    }
    #expect(result == "Mock response")
}

@Test func testTimedOutTaskPausesAndCanResume() async {
    let service = SubAgentTaskService(client: SlowMockClient())

    let info = await service.startTask(
        agentType: "researcher",
        description: "Slow task",
        prompt: "Do slow work",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .milliseconds(50),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    let pausedInfo = await service.waitForTask(id: info.id, timeout: .seconds(1))
    guard case .paused(let reason, _) = pausedInfo?.status else {
        Issue.record("Expected paused task but got \(String(describing: pausedInfo?.status))")
        return
    }
    #expect(reason == .deadlineExceeded)

    let resumed = await service.resumeTask(
        id: info.id,
        additionalInstructions: "Finish quickly",
        timeout: .seconds(1),
        maxSteps: nil
    )
    #expect(resumed != nil)

    let finalInfo = await service.waitForTask(id: info.id, timeout: .seconds(2))
    guard case .completed(let result) = finalInfo?.status else {
        Issue.record("Expected completed task after resume but got \(String(describing: finalInfo?.status))")
        return
    }
    #expect(result == "Slow response")
}

@Test func testCancelTaskMarksCancelled() async {
    let service = SubAgentTaskService(client: SlowMockClient())

    let info = await service.startTask(
        agentType: "researcher",
        description: "Cancelable task",
        prompt: "Do slow work",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .seconds(5),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    let cancelled = await service.cancelTask(id: info.id)
    #expect(cancelled)

    let updated = await service.getTask(id: info.id)
    guard case .cancelled = updated?.status else {
        Issue.record("Expected cancelled task but got \(String(describing: updated?.status))")
        return
    }
}

private struct FastMockClient: AgentCapableClient {
    typealias Model = String

    func executeAgentStep(
        messages: [LLMMessage],
        model: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        LLMResponse(
            content: [.text("Mock response")],
            model: "mock",
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            stopReason: .endTurn
        )
    }

    func planToolCalls(
        messages: [LLMMessage],
        model: String,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        ToolCallResponse(
            toolCalls: [],
            text: nil,
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            stopReason: .endTurn,
            model: "mock"
        )
    }

    func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: String,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        throw LLMError.emptyResponse
    }

    func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: String,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        throw LLMError.emptyResponse
    }
}

private struct SlowMockClient: AgentCapableClient {
    typealias Model = String

    func executeAgentStep(
        messages: [LLMMessage],
        model: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        thinkingMode: ThinkingMode,
        reasoningEffort: ReasoningEffort?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> LLMResponse {
        try await Task.sleep(for: .milliseconds(200))
        return LLMResponse(
            content: [.text("Slow response")],
            model: "mock",
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            stopReason: .endTurn
        )
    }

    func planToolCalls(
        messages: [LLMMessage],
        model: String,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        systemPrompt: SystemPrompt?,
        temperature: Double?,
        maxTokens: Int?,
        cachePolicy: PromptCachePolicy
    ) async throws -> ToolCallResponse {
        ToolCallResponse(
            toolCalls: [],
            text: nil,
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            stopReason: .endTurn,
            model: "mock"
        )
    }

    func generateWithUsage<T: StructuredProtocol>(
        input: LLMInput,
        model: String,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        throw LLMError.emptyResponse
    }

    func generateWithUsage<T: StructuredProtocol>(
        messages: [LLMMessage],
        model: String,
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> GenerationResult<T> {
        throw LLMError.emptyResponse
    }
}
