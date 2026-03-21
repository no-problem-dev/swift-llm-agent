import Foundation

/// プロジェクト CRUD プロトコル
public protocol ProjectStore: Sendable {
    func listProjects() async throws -> [Project]
    func getProject(id: UUID) async throws -> Project?
    func saveProject(_ project: Project) async throws
    func deleteProject(id: UUID) async throws
}

/// ファイルベースのプロジェクトストア
///
/// ストレージレイアウト:
/// ```
/// {baseDir}/{projectId}/project.json
/// ```
public actor FileProjectStore: ProjectStore {
    private let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func listProjects() async throws -> [Project] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDirectory.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        var projects: [Project] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for dir in contents {
            let projectFile = dir.appendingPathComponent("project.json")
            guard fm.fileExists(atPath: projectFile.path),
                  let data = fm.contents(atPath: projectFile.path) else { continue }
            do {
                let project = try decoder.decode(Project.self, from: data)
                projects.append(project)
            } catch {
                // Log decode error but continue to next project
                print("Failed to decode project at \(projectFile.path): \(error)")
            }
        }

        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func getProject(id: UUID) async throws -> Project? {
        let projectFile = projectFileURL(for: id)
        guard FileManager.default.fileExists(atPath: projectFile.path),
              let data = FileManager.default.contents(atPath: projectFile.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Project.self, from: data)
    }

    public func saveProject(_ project: Project) async throws {
        let projectDir = projectDirectoryURL(for: project.id)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: projectFileURL(for: project.id))
    }

    public func deleteProject(id: UUID) async throws {
        let projectDir = projectDirectoryURL(for: id)
        if FileManager.default.fileExists(atPath: projectDir.path) {
            try FileManager.default.removeItem(at: projectDir)
        }
    }

    // MARK: - Private

    private func projectDirectoryURL(for id: UUID) -> URL {
        baseDirectory.appendingPathComponent(id.uuidString)
    }

    private func projectFileURL(for id: UUID) -> URL {
        projectDirectoryURL(for: id).appendingPathComponent("project.json")
    }
}
