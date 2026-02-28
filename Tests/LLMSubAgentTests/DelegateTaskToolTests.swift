import Testing
import Foundation
@testable import LLMSubAgent
import LLMClient
import LLMTool
import LLMAgent

// MARK: - DelegateTaskTool Schema Tests

@Test func testToolNameAndDescription() {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    #expect(tool.toolName == "delegate_task")
    #expect(tool.toolDescription.contains("researcher"))
    #expect(tool.toolDescription.contains("Research agent"))
}

@Test func testInputSchemaContainsAgentTypes() throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
        SubAgentTypeDefinition(name: "writer", description: "Writer agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json: [String: Any]? = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    // properties が存在する
    let properties: [String: Any]? = json?["properties"] as? [String: Any]
    #expect(properties != nil)

    // agent_type に enum 値が含まれる
    let agentType: [String: Any]? = properties?["agent_type"] as? [String: Any]
    let enumValues = agentType?["enum"] as? [String]
    #expect(enumValues == ["researcher", "writer"])

    // required フィールドが正しい
    let required = json?["required"] as? [String]
    #expect(required?.contains("prompt") == true)
    #expect(required?.contains("description") == true)
    #expect(required?.contains("agent_type") == true)
}

@Test func testExecuteWithInvalidJSON() async throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    let invalidData = Data("not json".utf8)
    let result = try await tool.execute(with: invalidData)
    #expect(result.isError)
    #expect(result.stringValue.contains("Failed to decode"))
}

@Test func testExecuteWithUnknownAgentType() async throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    let args = [
        "prompt": "Do something",
        "description": "Test task",
        "agent_type": "nonexistent",
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)
    #expect(result.isError)
    #expect(result.stringValue.contains("Unknown agent type"))
    #expect(result.stringValue.contains("nonexistent"))
}

@Test func testDynamicDescriptionUpdatesWithCatalog() {
    let catalog1 = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "a", description: "Agent A")
    }

    let catalog2 = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "a", description: "Agent A")
        SubAgentTypeDefinition(name: "b", description: "Agent B")
    }

    let tool1 = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog1
    )

    let tool2 = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog2
    )

    #expect(!tool1.toolDescription.contains("Agent B"))
    #expect(tool2.toolDescription.contains("Agent B"))
}

@Test func testExecuteWithValidArguments() async throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    let args = [
        "prompt": "Research AI trends",
        "description": "AI research",
        "agent_type": "researcher",
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)
    #expect(!result.isError)
    #expect(result.stringValue == "Mock response")
}

// MARK: - Background Mode Schema Tests

@Test func testSchemaIncludesRunInBackgroundWithRegistry() throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let registry = BackgroundTaskRegistry()
    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog,
        backgroundTaskRegistry: registry
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json: [String: Any]? = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let properties: [String: Any]? = json?["properties"] as? [String: Any]

    #expect(properties?["run_in_background"] != nil)
}

@Test func testSchemaExcludesRunInBackgroundWithoutRegistry() throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json: [String: Any]? = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let properties: [String: Any]? = json?["properties"] as? [String: Any]

    #expect(properties?["run_in_background"] == nil)
}

@Test func testDescriptionIncludesBackgroundInfoWithRegistry() {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let registry = BackgroundTaskRegistry()
    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog,
        backgroundTaskRegistry: registry
    )

    #expect(tool.toolDescription.contains("run_in_background"))
    #expect(tool.toolDescription.contains("task_output"))
}

@Test func testBackgroundExecutionReturnsTaskId() async throws {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "researcher", description: "Research agent")
    }

    let registry = BackgroundTaskRegistry()
    let tool = DelegateTaskTool(
        client: MockAgentClient(),
        modelResolver: { _ in "test-model" },
        catalog: catalog,
        backgroundTaskRegistry: registry
    )

    let args: [String: Any] = [
        "prompt": "Research AI trends",
        "description": "AI research",
        "agent_type": "researcher",
        "run_in_background": true,
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("Background task started"))
    #expect(result.stringValue.contains("task_id:"))

    // Registry にタスクが登録されている
    let tasks = await registry.listTasks()
    #expect(tasks.count == 1)
    #expect(tasks[0].agentType == "researcher")
}

// MARK: - SubAgentError Tests

@Test func testSubAgentErrorDescriptions() {
    let errors: [(SubAgentError, String)] = [
        (.maxStepsExceeded(steps: 10), "10"),
        (.emptyResponse, "empty"),
        (.timeout(.seconds(30)), "30"),
        (.invalidArguments("bad"), "bad"),
    ]

    for (error, expectedSubstring) in errors {
        let description = error.localizedDescription
        #expect(description.contains(expectedSubstring), "Expected '\(expectedSubstring)' in '\(description)'")
    }
}

// MARK: - Mock Client

/// テスト用のモッククライアント
private struct MockAgentClient: AgentCapableClient {
    typealias Model = String

    func executeAgentStep(
        messages: [LLMMessage],
        model: String,
        systemPrompt: SystemPrompt?,
        tools: ToolSet,
        toolChoice: ToolChoice?,
        responseSchema: JSONSchema?,
        maxTokens: Int?
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
        systemPrompt: String?,
        temperature: Double?,
        maxTokens: Int?
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
