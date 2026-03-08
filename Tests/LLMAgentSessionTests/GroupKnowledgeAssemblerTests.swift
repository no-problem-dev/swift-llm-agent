import Foundation
import Testing
import LLMClient
import AgentCommunication
@testable import LLMAgentSession

@Suite("GroupKnowledgeAssembler Tests")
struct GroupKnowledgeAssemblerTests {

    @Test("Returns empty for store with no core topics")
    func emptyCoreTopics() async throws {
        let store = InMemoryKnowledgeStore()
        let topic = KnowledgeTopic(name: "non-core", isCore: false)
        try await store.saveTopic(topic)

        let assembler = GroupKnowledgeAssembler()
        let components = try await assembler.promptComponents(from: store)
        #expect(components.isEmpty)
    }

    @Test("Renders core topics as context component")
    func rendersCoreTopics() async throws {
        let store = InMemoryKnowledgeStore()
        let topic = KnowledgeTopic(
            name: "architecture",
            summary: "App architecture decisions",
            entries: [KnowledgeEntry(content: "MVVM + UIRouting pattern")],
            isCore: true
        )
        try await store.saveTopic(topic)

        let assembler = GroupKnowledgeAssembler()
        let components = try await assembler.promptComponents(from: store)

        #expect(components.count == 1)

        if case .context(let text) = components.first {
            #expect(text.contains("group_knowledge:"))
            #expect(text.contains("architecture"))
            #expect(text.contains("MVVM + UIRouting pattern"))
        } else {
            Issue.record("Expected .context component")
        }
    }

    @Test("Custom label is used")
    func customLabel() async throws {
        let store = InMemoryKnowledgeStore()
        let topic = KnowledgeTopic(
            name: "test",
            entries: [KnowledgeEntry(content: "content")],
            isCore: true
        )
        try await store.saveTopic(topic)

        let assembler = GroupKnowledgeAssembler()
        let components = try await assembler.promptComponents(
            from: store,
            label: "workspace_knowledge"
        )

        if case .context(let text) = components.first {
            #expect(text.hasPrefix("workspace_knowledge:"))
        } else {
            Issue.record("Expected .context component")
        }
    }

    @Test("Truncates when character limit exceeded")
    func truncation() async throws {
        let store = InMemoryKnowledgeStore()
        let entries = (0..<100).map {
            KnowledgeEntry(content: "Entry \($0) with some longer content to fill up space")
        }
        let topic = KnowledgeTopic(
            name: "big-topic",
            entries: entries,
            isCore: true
        )
        try await store.saveTopic(topic)

        let assembler = GroupKnowledgeAssembler(characterLimit: 200)
        let components = try await assembler.promptComponents(from: store)

        if case .context(let text) = components.first {
            #expect(text.contains("truncated"))
        } else {
            Issue.record("Expected .context component")
        }
    }

    @Test("renderCoreKnowledge returns empty string for no core topics")
    func renderCoreKnowledgeEmpty() async throws {
        let store = InMemoryKnowledgeStore()
        let assembler = GroupKnowledgeAssembler()
        let result = try await assembler.renderCoreKnowledge(from: store)
        #expect(result.isEmpty)
    }

    @Test("renderCoreKnowledge includes summary")
    func renderCoreKnowledgeWithSummary() async throws {
        let store = InMemoryKnowledgeStore()
        let topic = KnowledgeTopic(
            name: "patterns",
            summary: "Design patterns used",
            entries: [KnowledgeEntry(content: "Repository pattern")],
            isCore: true
        )
        try await store.saveTopic(topic)

        let assembler = GroupKnowledgeAssembler()
        let result = try await assembler.renderCoreKnowledge(from: store)

        #expect(result.contains("## patterns"))
        #expect(result.contains("Design patterns used"))
        #expect(result.contains("- Repository pattern"))
    }

    @Test("Multiple core topics are rendered")
    func multipleCoreTopics() async throws {
        let store = InMemoryKnowledgeStore()
        let t1 = KnowledgeTopic(
            name: "arch",
            entries: [KnowledgeEntry(content: "MVVM")],
            isCore: true
        )
        let t2 = KnowledgeTopic(
            name: "prefs",
            entries: [KnowledgeEntry(content: "Dark mode")],
            isCore: true
        )
        try await store.saveTopic(t1)
        try await store.saveTopic(t2)

        let assembler = GroupKnowledgeAssembler()
        let result = try await assembler.renderCoreKnowledge(from: store)

        #expect(result.contains("## arch"))
        #expect(result.contains("MVVM"))
        #expect(result.contains("## prefs"))
        #expect(result.contains("Dark mode"))
    }
}
