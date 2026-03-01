import Foundation
import Testing
@testable import LLMProject

@Suite("FileProjectStore Tests")
struct FileProjectStoreTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMProjectTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    @Test("Save and retrieve a project")
    func saveAndGet() async throws {
        let store = FileProjectStore(baseDirectory: tempDir)
        let project = Project(name: "Test Project", description: "A test")

        try await store.saveProject(project)
        let retrieved = try await store.getProject(id: project.id)

        #expect(retrieved != nil)
        #expect(retrieved?.name == "Test Project")
        #expect(retrieved?.description == "A test")
    }

    @Test("List projects returns all saved projects")
    func listProjects() async throws {
        let store = FileProjectStore(baseDirectory: tempDir)
        let p1 = Project(name: "Alpha")
        let p2 = Project(name: "Beta")

        try await store.saveProject(p1)
        try await store.saveProject(p2)

        let projects = try await store.listProjects()
        #expect(projects.count == 2)
        let names = Set(projects.map(\.name))
        #expect(names.contains("Alpha"))
        #expect(names.contains("Beta"))
    }

    @Test("Delete project removes it")
    func deleteProject() async throws {
        let store = FileProjectStore(baseDirectory: tempDir)
        let project = Project(name: "ToDelete")

        try await store.saveProject(project)
        try await store.deleteProject(id: project.id)

        let retrieved = try await store.getProject(id: project.id)
        #expect(retrieved == nil)
    }

    @Test("Get non-existent project returns nil")
    func getNonExistent() async throws {
        let store = FileProjectStore(baseDirectory: tempDir)
        let result = try await store.getProject(id: UUID())
        #expect(result == nil)
    }

    @Test("Update project preserves changes")
    func updateProject() async throws {
        let store = FileProjectStore(baseDirectory: tempDir)
        var project = Project(name: "Original")
        try await store.saveProject(project)

        project.name = "Updated"
        project.configuration.instructions = "New instructions"
        try await store.saveProject(project)

        let retrieved = try await store.getProject(id: project.id)
        #expect(retrieved?.name == "Updated")
        #expect(retrieved?.configuration.instructions == "New instructions")
    }
}
