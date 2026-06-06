import Testing
import Foundation
@testable import LLMSubAgent
import LLMClient
import LLMTool
import LLMAgent

@Test func testWaitTaskToolReturnsTaskState() async throws {
    let service = SubAgentTaskService(client: FastMockClient())
    let info = await service.startTask(
        agentType: "researcher",
        description: "Task",
        prompt: "Research",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .seconds(5),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    let tool = WaitTaskTool(controller: service)
    let args = [
        "task_id": info.id.uuidString,
        "timeout_seconds": 1,
    ] as [String : Any]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("task_id:"))
    #expect(result.stringValue.contains("status: completed"))
}

@Test func testResumeTaskToolResumesPausedTask() async throws {
    let service = SubAgentTaskService(client: SlowMockClient())
    let info = await service.startTask(
        agentType: "researcher",
        description: "Task",
        prompt: "Research",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .milliseconds(50),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    _ = await service.waitForTask(id: info.id, timeout: .seconds(1))

    let tool = ResumeTaskTool(controller: service)
    let args = [
        "task_id": info.id.uuidString,
        "timeout_seconds": 1,
        "await_timeout_seconds": 2,
    ] as [String : Any]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("status: completed"))
}

@Test func testListAndCancelTools() async throws {
    let service = SubAgentTaskService(client: SlowMockClient())
    let info = await service.startTask(
        agentType: "researcher",
        description: "Task",
        prompt: "Research",
        model: "mock",
        tools: ToolSet(),
        systemPrompt: nil,
        configuration: .default,
        timeout: .seconds(5),
        maxStepsOverride: nil,
        maxAttempts: 2
    )

    let listTool = ListTasksTool(controller: service)
    let listData = try JSONSerialization.data(withJSONObject: [:])
    let listResult = try await listTool.execute(with: listData)
    #expect(!listResult.isError)
    #expect(listResult.stringValue.contains(info.id.uuidString))

    let cancelTool = CancelTaskTool(controller: service)
    let cancelData = try JSONSerialization.data(withJSONObject: ["task_id": info.id.uuidString])
    let cancelResult = try await cancelTool.execute(with: cancelData)
    #expect(!cancelResult.isError)
    #expect(cancelResult.stringValue.contains("status: cancelled"))
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
