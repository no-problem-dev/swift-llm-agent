import Testing
import Foundation
@testable import LLMSkill
import LLMSubAgent
import LLMClient
import LLMTool
import LLMAgent

// MARK: - SkillTool Schema Tests

@Test func testToolNameAndDescription() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarizes text content",
            instructions: "Create a concise summary..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    #expect(tool.toolName == "use_skill")
    #expect(tool.toolDescription.contains("summarize"))
    #expect(tool.toolDescription.contains("Summarizes text content"))
}

@Test func testInputSchemaContainsSkillNames() throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarize",
            instructions: "..."
        )
        AgentSkillDefinition(
            name: "translate",
            description: "Translate",
            instructions: "..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    let properties = json?["properties"] as? [String: Any]
    #expect(properties != nil)

    let skillName = properties?["skill_name"] as? [String: Any]
    let enumValues = skillName?["enum"] as? [String]
    #expect(enumValues == ["summarize", "translate"])

    let required = json?["required"] as? [String]
    #expect(required?.contains("skill_name") == true)
    #expect(required?.contains("argument") == true)
}

@Test func testNonModelInvocableSkillExcludedFromSchema() throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "visible",
            description: "Visible to model",
            instructions: "...",
            isModelInvocable: true
        )
        AgentSkillDefinition(
            name: "hidden",
            description: "Hidden from model",
            instructions: "...",
            isModelInvocable: false
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let properties = json?["properties"] as? [String: Any]
    let skillName = properties?["skill_name"] as? [String: Any]
    let enumValues = skillName?["enum"] as? [String]

    #expect(enumValues == ["visible"])
    #expect(tool.toolDescription.contains("visible"))
    #expect(!tool.toolDescription.contains("hidden"))
}

@Test func testForkSkillShowsForkMarker() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Deep research",
            executionMode: .fork,
            instructions: "..."
        )
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarize",
            executionMode: .inline,
            instructions: "..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    #expect(tool.toolDescription.contains("[fork]"))
    // inline スキルには [fork] マーカーがない
    let lines = tool.toolDescription.components(separatedBy: "\n")
    let summarizeLine = lines.first { $0.contains("summarize") }
    #expect(summarizeLine != nil)
    #expect(!summarizeLine!.contains("[fork]"))
}

// MARK: - Inline Execution Tests

@Test func testInlineExecutionReturnsInstructions() async throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarize",
            executionMode: .inline,
            instructions: "Create a concise summary with bullet points."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let args: [String: Any] = [
        "skill_name": "summarize",
        "argument": "Summarize the quarterly report",
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("skill_instructions"))
    #expect(result.stringValue.contains("summarize"))
    #expect(result.stringValue.contains("Create a concise summary with bullet points."))
    #expect(result.stringValue.contains("user_request"))
    #expect(result.stringValue.contains("Summarize the quarterly report"))
}

// MARK: - Forked Execution Tests

@Test func testForkedExecutionCallsSubAgent() async throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Research a topic",
            executionMode: .fork,
            instructions: "Research the given topic thoroughly."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let args: [String: Any] = [
        "skill_name": "research",
        "argument": "Research AI trends",
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue == "Mock response")
}

// MARK: - Error Handling Tests

@Test func testExecuteWithInvalidJSON() async throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "test",
            description: "Test",
            instructions: "..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let invalidData = Data("not json".utf8)
    let result = try await tool.execute(with: invalidData)
    #expect(result.isError)
    #expect(result.stringValue.contains("Failed to decode"))
}

@Test func testExecuteWithUnknownSkill() async throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarize",
            instructions: "..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let args: [String: Any] = [
        "skill_name": "nonexistent",
        "argument": "Do something",
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)
    #expect(result.isError)
    #expect(result.stringValue.contains("Unknown skill"))
    #expect(result.stringValue.contains("nonexistent"))
}

// MARK: - Background Mode Tests

@Test func testSchemaIncludesRunInBackgroundWithRegistry() throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Research",
            executionMode: .fork,
            instructions: "..."
        )
    }

    let bgRegistry = BackgroundTaskRegistry()
    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry,
        backgroundTaskRegistry: bgRegistry
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let properties = json?["properties"] as? [String: Any]

    #expect(properties?["run_in_background"] != nil)
}

@Test func testSchemaExcludesRunInBackgroundWithoutRegistry() throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Research",
            executionMode: .fork,
            instructions: "..."
        )
    }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let properties = json?["properties"] as? [String: Any]

    #expect(properties?["run_in_background"] == nil)
}

@Test func testDescriptionIncludesBackgroundInfoWithRegistry() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Research",
            executionMode: .fork,
            instructions: "..."
        )
    }

    let bgRegistry = BackgroundTaskRegistry()
    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry,
        backgroundTaskRegistry: bgRegistry
    )

    #expect(tool.toolDescription.contains("run_in_background"))
    #expect(tool.toolDescription.contains("task_output"))
}

@Test func testBackgroundExecutionReturnsTaskId() async throws {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "research",
            description: "Research",
            executionMode: .fork,
            instructions: "Research thoroughly."
        )
    }

    let bgRegistry = BackgroundTaskRegistry()
    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry,
        backgroundTaskRegistry: bgRegistry
    )

    let args: [String: Any] = [
        "skill_name": "research",
        "argument": "Research AI trends",
        "run_in_background": true,
    ]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("Background skill started"))
    #expect(result.stringValue.contains("task_id:"))

    let tasks = await bgRegistry.listTasks()
    #expect(tasks.count == 1)
    #expect(tasks[0].agentType == "skill:research")
}

// MARK: - Empty Registry Test

@Test func testEmptyRegistryDescription() {
    let registry = SkillRegistryDefinition { }

    let tool = SkillTool(
        client: MockAgentClient(),
        model: "test-model",
        registry: registry
    )

    #expect(tool.toolDescription == "No skills available.")
}

// MARK: - Mock Client

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
