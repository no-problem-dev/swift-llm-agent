import Foundation
import Testing
import LLMClient
import LLMTool
import LLMAgent
import LLMAgentSession
@testable import LLMProject

@Suite("ProjectContextAssembler Tests")
struct ProjectContextAssemblerTests {
    let tempDir: URL
    let projectId: UUID

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMProjectAssemblerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        projectId = UUID()
    }

    @Test("Apply injects instructions into SystemPrompt")
    func injectsInstructions() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let project = Project(
            id: projectId,
            name: "Test",
            configuration: ProjectConfiguration(instructions: "Always respond in Japanese.")
        )

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let config = TurnConfiguration(systemPrompt: SystemPrompt {
            PromptComponent.role("Assistant")
        })

        let result = try await assembler.apply(project, to: config)
        let rendered = result.systemPrompt?.render() ?? ""

        #expect(rendered.contains("project_instructions"))
        #expect(rendered.contains("Always respond in Japanese."))
        #expect(rendered.contains("Assistant"))
    }

    @Test("Apply injects core knowledge when policy is coreAlways")
    func injectsCoreKnowledge() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let coreTopic = KnowledgeTopic(
            name: "architecture",
            summary: "App architecture decisions",
            entries: [KnowledgeEntry(content: "MVVM + UIRouting pattern")],
            isCore: true
        )
        try await store.saveTopic(coreTopic, projectId: projectId)

        let project = Project(
            id: projectId,
            name: "Test",
            configuration: ProjectConfiguration(knowledgePolicy: .coreAlways)
        )

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let config = TurnConfiguration()
        let result = try await assembler.apply(project, to: config)
        let rendered = result.systemPrompt?.render() ?? ""

        #expect(rendered.contains("project_knowledge"))
        #expect(rendered.contains("architecture"))
        #expect(rendered.contains("MVVM + UIRouting pattern"))
    }

    @Test("Apply skips core knowledge when policy is toolOnly")
    func skipsCoreKnowledgeForToolOnly() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let coreTopic = KnowledgeTopic(
            name: "architecture",
            entries: [KnowledgeEntry(content: "MVVM")],
            isCore: true
        )
        try await store.saveTopic(coreTopic, projectId: projectId)

        let project = Project(
            id: projectId,
            name: "Test",
            configuration: ProjectConfiguration(knowledgePolicy: .toolOnly)
        )

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let config = TurnConfiguration()
        let result = try await assembler.apply(project, to: config)
        let rendered = result.systemPrompt?.render() ?? ""

        // The behavior prompt still mentions tools, but no knowledge context block
        #expect(!rendered.contains("project_knowledge:"))
        #expect(!rendered.contains("MVVM"))
    }

    @Test("Apply adds knowledge tools to ToolSet")
    func addsKnowledgeTools() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let project = Project(id: projectId, name: "Test")

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let config = TurnConfiguration()
        let result = try await assembler.apply(project, to: config)

        let toolNames = result.tools.tools.map(\.toolName)
        #expect(toolNames.contains("project_knowledge_list"))
        #expect(toolNames.contains("project_knowledge_read"))
        #expect(toolNames.contains("project_knowledge_search"))
        #expect(toolNames.contains("project_knowledge_save"))
        #expect(toolNames.contains("project_knowledge_remove"))
        #expect(toolNames.contains("project_knowledge_set_core"))
    }

    @Test("Apply injects behavior prompt for knowledge management")
    func injectsBehaviorPrompt() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let project = Project(id: projectId, name: "Test")

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let config = TurnConfiguration()
        let result = try await assembler.apply(project, to: config)
        let rendered = result.systemPrompt?.render() ?? ""

        #expect(rendered.contains("project_knowledge_save"))
        #expect(rendered.contains("persist across sessions"))
    }

    @Test("Apply preserves existing tools")
    func preservesExistingTools() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let project = Project(id: projectId, name: "Test")

        let assembler = ProjectContextAssembler(knowledgeStore: store)
        let existingTool = DummyTool(toolName: "existing_tool")
        let config = TurnConfiguration(tools: ToolSet(tools: [existingTool]))
        let result = try await assembler.apply(project, to: config)

        let toolNames = result.tools.tools.map(\.toolName)
        #expect(toolNames.contains("existing_tool"))
        #expect(toolNames.contains("project_knowledge_list"))
    }

    @Test("Core knowledge respects character limit")
    func respectsCharacterLimit() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        // Create a core topic with many entries
        let entries = (0..<100).map { KnowledgeEntry(content: "Entry \($0) with some longer content to fill up space") }
        let coreTopic = KnowledgeTopic(
            name: "big-topic",
            entries: entries,
            isCore: true
        )
        try await store.saveTopic(coreTopic, projectId: projectId)

        let project = Project(
            id: projectId,
            name: "Test",
            configuration: ProjectConfiguration(knowledgePolicy: .coreAlways)
        )

        let assembler = ProjectContextAssembler(
            knowledgeStore: store,
            coreKnowledgeCharacterLimit: 200
        )
        let config = TurnConfiguration()
        let result = try await assembler.apply(project, to: config)
        let rendered = result.systemPrompt?.render() ?? ""

        #expect(rendered.contains("truncated"))
    }
}

// MARK: - Test Helpers

private struct DummyTool: Tool, Sendable {
    let toolName: String
    let toolDescription: String = "A dummy tool for testing"
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    func execute(with argumentsData: Data) async throws -> ToolResult {
        .text("ok")
    }
}
