import Foundation
import Testing
@testable import LLMProject

@Suite("FileProjectKnowledgeStore Tests")
struct FileProjectKnowledgeStoreTests {
    let tempDir: URL
    let projectId: UUID

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMProjectKnowledgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        projectId = UUID()
    }

    @Test("Add entry creates topic automatically")
    func addEntryAutoCreates() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let entry = KnowledgeEntry(content: "MVVM architecture")

        try await store.addEntry(entry, toTopic: "architecture", projectId: projectId)

        let topic = try await store.getTopic(projectId: projectId, named: "architecture")
        #expect(topic != nil)
        #expect(topic?.entries.count == 1)
        #expect(topic?.entries.first?.content == "MVVM architecture")
    }

    @Test("List topics returns all topics")
    func listTopics() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let t1 = KnowledgeTopic(name: "architecture", summary: "App architecture")
        let t2 = KnowledgeTopic(name: "preferences", summary: "User prefs")

        try await store.saveTopic(t1, projectId: projectId)
        try await store.saveTopic(t2, projectId: projectId)

        let topics = try await store.listTopics(projectId: projectId)
        #expect(topics.count == 2)
    }

    @Test("Get core topics filters correctly")
    func getCoreTopics() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let core = KnowledgeTopic(name: "core-topic", isCore: true)
        let nonCore = KnowledgeTopic(name: "non-core", isCore: false)

        try await store.saveTopic(core, projectId: projectId)
        try await store.saveTopic(nonCore, projectId: projectId)

        let coreTopics = try await store.getCoreTopics(projectId: projectId)
        #expect(coreTopics.count == 1)
        #expect(coreTopics.first?.name == "core-topic")
    }

    @Test("Remove entry removes specific entry")
    func removeEntry() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let e1 = KnowledgeEntry(content: "First")
        let e2 = KnowledgeEntry(content: "Second")
        let topic = KnowledgeTopic(name: "test", entries: [e1, e2])

        try await store.saveTopic(topic, projectId: projectId)
        try await store.removeEntry(entryId: e1.id, fromTopic: "test", projectId: projectId)

        let updated = try await store.getTopic(projectId: projectId, named: "test")
        #expect(updated?.entries.count == 1)
        #expect(updated?.entries.first?.content == "Second")
    }

    @Test("Delete topic removes it")
    func deleteTopic() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(name: "to-delete")

        try await store.saveTopic(topic, projectId: projectId)
        try await store.deleteTopic(projectId: projectId, topicId: topic.id)

        let retrieved = try await store.getTopic(projectId: projectId, named: "to-delete")
        #expect(retrieved == nil)
    }

    @Test("Search finds matching entries")
    func searchFindsMatches() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let e1 = KnowledgeEntry(content: "SwiftUI uses declarative syntax")
        let e2 = KnowledgeEntry(content: "UIKit is imperative")
        let topic = KnowledgeTopic(name: "ios", summary: "iOS development", entries: [e1, e2])

        try await store.saveTopic(topic, projectId: projectId)

        let results = try await store.search(query: "declarative", projectId: projectId)
        #expect(results.count == 1)
        #expect(results.first?.entry.content == "SwiftUI uses declarative syntax")
    }

    @Test("Search returns empty for no matches")
    func searchNoMatches() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(
            name: "test",
            entries: [KnowledgeEntry(content: "Hello")]
        )
        try await store.saveTopic(topic, projectId: projectId)

        let results = try await store.search(query: "nonexistent", projectId: projectId)
        #expect(results.isEmpty)
    }

    @Test("Topic name sanitization handles special characters")
    func topicNameSanitization() async throws {
        let store = FileProjectKnowledgeStore(baseDirectory: tempDir)
        let topic = KnowledgeTopic(name: "user preferences & settings")

        try await store.saveTopic(topic, projectId: projectId)
        let retrieved = try await store.getTopic(projectId: projectId, named: "user preferences & settings")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "user preferences & settings")
    }
}
