import Testing
import Foundation
@testable import LLMSubAgent
import LLMClient

// MARK: - Tool Identity

@Test func testOutputToolNameAndDescription() {
    let registry = BackgroundTaskRegistry()
    let tool = BackgroundTaskOutputTool(registry: registry)

    #expect(tool.toolName == "task_output")
    #expect(tool.toolDescription.contains("background task"))
}

// MARK: - Input Schema

@Test func testOutputToolInputSchema() throws {
    let registry = BackgroundTaskRegistry()
    let tool = BackgroundTaskOutputTool(registry: registry)

    let schema = tool.inputSchema
    let data = try schema.toJSONData()
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    let properties = json?["properties"] as? [String: Any]
    #expect(properties?["task_id"] != nil)
    #expect(properties?["timeout_seconds"] != nil)

    let required = json?["required"] as? [String]
    #expect(required?.contains("task_id") == true)
    #expect(required?.contains("timeout_seconds") != true)
}

// MARK: - Completed Task

@Test func testOutputToolCompletedTask() async throws {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(taskId: taskId, agentType: "researcher", description: "Test", taskHandle: handle)
    await registry.markCompleted(taskId: taskId, result: "Research result")

    let tool = BackgroundTaskOutputTool(registry: registry)
    let args = ["task_id": taskId.uuidString]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue == "Research result")
}

// MARK: - Running Task

@Test func testOutputToolRunningTask() async throws {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(taskId: taskId, agentType: "researcher", description: "Test", taskHandle: handle)

    let tool = BackgroundTaskOutputTool(registry: registry)
    let args = ["task_id": taskId.uuidString]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(!result.isError)
    #expect(result.stringValue.contains("still running"))
}

// MARK: - Unknown Task

@Test func testOutputToolUnknownTask() async throws {
    let registry = BackgroundTaskRegistry()
    let tool = BackgroundTaskOutputTool(registry: registry)

    let args = ["task_id": UUID().uuidString]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(result.isError)
    #expect(result.stringValue.contains("not found"))
}

// MARK: - Invalid Arguments

@Test func testOutputToolInvalidTaskId() async throws {
    let registry = BackgroundTaskRegistry()
    let tool = BackgroundTaskOutputTool(registry: registry)

    let args = ["task_id": "not-a-uuid"]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(result.isError)
    #expect(result.stringValue.contains("Invalid task_id"))
}

@Test func testOutputToolInvalidJSON() async throws {
    let registry = BackgroundTaskRegistry()
    let tool = BackgroundTaskOutputTool(registry: registry)

    let data = Data("not json".utf8)
    let result = try await tool.execute(with: data)

    #expect(result.isError)
    #expect(result.stringValue.contains("Failed to decode"))
}

// MARK: - Failed Task

@Test func testOutputToolFailedTask() async throws {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(taskId: taskId, agentType: "researcher", description: "Test", taskHandle: handle)
    await registry.markFailed(taskId: taskId, error: "API error")

    let tool = BackgroundTaskOutputTool(registry: registry)
    let args = ["task_id": taskId.uuidString]
    let data = try JSONSerialization.data(withJSONObject: args)
    let result = try await tool.execute(with: data)

    #expect(result.isError)
    #expect(result.stringValue.contains("API error"))
}
