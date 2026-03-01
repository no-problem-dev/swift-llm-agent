import Testing
import Foundation
@testable import LLMMCP

// MARK: - Workspace Tests

@Test func testWorkspaceCreation() {
    let workspace = Workspace(
        workingDirectory: "/tmp/test/work",
        rootDirectory: "/tmp/test"
    )
    #expect(workspace.workingDirectory == "/tmp/test/work")
    #expect(workspace.rootDirectory == "/tmp/test")
    #expect(workspace.source == .automatic)
}

@Test func testWorkspaceWithUserSpecifiedSource() {
    let workspace = Workspace(
        workingDirectory: "/custom/path",
        rootDirectory: "/custom",
        source: .userSpecified(path: "/custom")
    )
    #expect(workspace.source == .userSpecified(path: "/custom"))
}

@Test func testWorkspaceEquatable() {
    let id = UUID()
    let w1 = Workspace(id: id, workingDirectory: "/tmp/a", rootDirectory: "/tmp")
    let w2 = Workspace(id: id, workingDirectory: "/tmp/a", rootDirectory: "/tmp")
    #expect(w1 == w2)
}

@Test func testWorkspaceIdentifiable() {
    let workspace = Workspace(
        workingDirectory: "/tmp/test",
        rootDirectory: "/tmp"
    )
    #expect(workspace.id != UUID())
}

// MARK: - WorkspaceSource Tests

@Test func testWorkspaceSourceEquatable() {
    #expect(WorkspaceSource.automatic == WorkspaceSource.automatic)
    #expect(WorkspaceSource.userSpecified(path: "/a") == WorkspaceSource.userSpecified(path: "/a"))
    #expect(WorkspaceSource.automatic != WorkspaceSource.userSpecified(path: "/a"))
}

// MARK: - WorkspaceProvider Tests

@Test func testWorkspaceProviderCreateAndGet() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("workspace-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let provider = WorkspaceProvider(baseDirectory: tempDir.path)
    let sessionId = UUID()

    let workspace = try await provider.createWorkspace(for: sessionId)
    #expect(workspace.id == sessionId)
    #expect(workspace.source == .automatic)

    // Verify directory was created
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: workspace.rootDirectory, isDirectory: &isDir)
    #expect(exists == true)
    #expect(isDir.boolValue == true)

    // Get workspace
    let retrieved = await provider.workspace(for: sessionId)
    #expect(retrieved != nil)
    #expect(retrieved?.id == sessionId)
}

@Test func testWorkspaceProviderRemove() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("workspace-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let provider = WorkspaceProvider(baseDirectory: tempDir.path)
    let sessionId = UUID()

    let workspace = try await provider.createWorkspace(for: sessionId)
    let rootDir = workspace.rootDirectory

    await provider.removeWorkspace(for: sessionId)

    let retrieved = await provider.workspace(for: sessionId)
    #expect(retrieved == nil)

    let exists = FileManager.default.fileExists(atPath: rootDir)
    #expect(exists == false)
}

@Test func testWorkspaceProviderRemoveAll() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("workspace-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let provider = WorkspaceProvider(baseDirectory: tempDir.path)
    let id1 = UUID()
    let id2 = UUID()

    _ = try await provider.createWorkspace(for: id1)
    _ = try await provider.createWorkspace(for: id2)

    await provider.removeAll()

    let w1 = await provider.workspace(for: id1)
    let w2 = await provider.workspace(for: id2)
    #expect(w1 == nil)
    #expect(w2 == nil)
}

@Test func testWorkspaceProviderGetNonExistent() async {
    let provider = WorkspaceProvider(baseDirectory: "/tmp/nonexistent")
    let workspace = await provider.workspace(for: UUID())
    #expect(workspace == nil)
}
