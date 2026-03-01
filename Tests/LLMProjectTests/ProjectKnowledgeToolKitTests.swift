import Foundation
import Testing
import LLMTool
@testable import LLMProject

@Suite("ProjectKnowledgeToolKit Tests")
struct ProjectKnowledgeToolKitTests {
    let tempDir: URL
    let projectId: UUID

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMProjectToolKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        projectId = UUID()
    }

    @Test("ToolKit provides 6 tools")
    func toolCount() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)

        #expect(toolkit.tools.count == 6)
        let names = toolkit.toolNames
        #expect(names.contains("project_knowledge_list"))
        #expect(names.contains("project_knowledge_read"))
        #expect(names.contains("project_knowledge_search"))
        #expect(names.contains("project_knowledge_save"))
        #expect(names.contains("project_knowledge_remove"))
        #expect(names.contains("project_knowledge_set_core"))
    }

    @Test("Save tool creates entry")
    func saveTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)

        let input = """
        {"topic": "architecture", "content": "Uses MVVM pattern", "summary": "Architecture decisions"}
        """
        let tool = toolkit.tool(named: "project_knowledge_save")!
        let result = try await tool.execute(with: input.data(using: .utf8)!)

        #expect(result.textContent.contains("Saved"))

        let topic = try await store.getTopic(projectId: projectId, named: "architecture")
        #expect(topic != nil)
        #expect(topic?.summary == "Architecture decisions")
        #expect(topic?.entries.count == 1)
    }

    @Test("List tool returns topics")
    func listTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(
            name: "test-topic",
            summary: "Test",
            entries: [KnowledgeEntry(content: "Hello")]
        )
        try await store.saveTopic(topic, projectId: projectId)

        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_list")!
        let result = try await tool.execute(with: "{}".data(using: .utf8)!)

        #expect(result.textContent.contains("test-topic"))
    }

    @Test("Read tool returns topic contents")
    func readTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(
            name: "architecture",
            entries: [KnowledgeEntry(content: "MVVM pattern")]
        )
        try await store.saveTopic(topic, projectId: projectId)

        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_read")!
        let result = try await tool.execute(with: """
        {"topic": "architecture"}
        """.data(using: .utf8)!)

        #expect(result.textContent.contains("MVVM pattern"))
    }

    @Test("Read tool returns not found for missing topic")
    func readToolNotFound() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_read")!
        let result = try await tool.execute(with: """
        {"topic": "nonexistent"}
        """.data(using: .utf8)!)

        #expect(result.textContent.contains("not found"))
    }

    @Test("Search tool finds matching entries")
    func searchTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(
            name: "ios",
            entries: [KnowledgeEntry(content: "SwiftUI declarative syntax")]
        )
        try await store.saveTopic(topic, projectId: projectId)

        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_search")!
        let result = try await tool.execute(with: """
        {"query": "SwiftUI"}
        """.data(using: .utf8)!)

        #expect(result.textContent.contains("declarative"))
    }

    @Test("Set core tool toggles core flag")
    func setCoreTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(name: "prefs", isCore: false)
        try await store.saveTopic(topic, projectId: projectId)

        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_set_core")!
        let result = try await tool.execute(with: """
        {"topic": "prefs", "isCore": true}
        """.data(using: .utf8)!)

        #expect(result.textContent.contains("core"))

        let updated = try await store.getTopic(projectId: projectId, named: "prefs")
        #expect(updated?.isCore == true)
    }

    @Test("Remove tool removes entry by ID")
    func removeTool() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let entry = KnowledgeEntry(content: "To be removed")
        let topic = KnowledgeTopic(name: "test", entries: [entry])
        try await store.saveTopic(topic, projectId: projectId)

        let toolkit = ProjectKnowledgeToolKit(store: store, projectId: projectId)
        let tool = toolkit.tool(named: "project_knowledge_remove")!
        let result = try await tool.execute(with: """
        {"topic": "test", "entryId": "\(entry.id.uuidString)"}
        """.data(using: .utf8)!)

        #expect(result.textContent.contains("Removed"))

        let updated = try await store.getTopic(projectId: projectId, named: "test")
        #expect(updated?.entries.isEmpty == true)
    }
}

// MARK: - ToolResult text helper

private extension ToolResult {
    var textContent: String {
        switch self {
        case .text(let s): return s
        case .json(let data): return String(data: data, encoding: .utf8) ?? ""
        case .error(let s): return s
        default: return ""
        }
    }
}
