import Foundation

/// プロジェクトナレッジストア プロトコル
public protocol ProjectKnowledgeStore: Sendable {
    func listTopics(projectId: UUID) async throws -> [KnowledgeTopic]
    func getCoreTopics(projectId: UUID) async throws -> [KnowledgeTopic]
    func getTopic(projectId: UUID, named: String) async throws -> KnowledgeTopic?
    func saveTopic(_ topic: KnowledgeTopic, projectId: UUID) async throws
    func deleteTopic(projectId: UUID, topicId: UUID) async throws
    func addEntry(_ entry: KnowledgeEntry, toTopic topicName: String, projectId: UUID) async throws
    func removeEntry(entryId: UUID, fromTopic topicName: String, projectId: UUID) async throws
    func search(query: String, projectId: UUID) async throws -> [KnowledgeSearchResult]
}

/// ファイルベースのナレッジストア
///
/// ストレージレイアウト:
/// ```
/// {baseDir}/{projectId}/knowledge/{topicName}.json
/// ```
///
/// トピック名をファイル名にすることで人間可読なストレージを実現。
public actor FileProjectKnowledgeStore: ProjectKnowledgeStore {
    private let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func listTopics(projectId: UUID) async throws -> [KnowledgeTopic] {
        let knowledgeDir = knowledgeDirectoryURL(for: projectId)
        let fm = FileManager.default
        guard fm.fileExists(atPath: knowledgeDir.path) else { return [] }

        let files = try fm.contentsOfDirectory(
            at: knowledgeDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var topics: [KnowledgeTopic] = []
        for file in files {
            if let data = fm.contents(atPath: file.path),
               let topic = try? decoder.decode(KnowledgeTopic.self, from: data) {
                topics.append(topic)
            }
        }

        return topics.sorted { $0.name < $1.name }
    }

    public func getCoreTopics(projectId: UUID) async throws -> [KnowledgeTopic] {
        try await listTopics(projectId: projectId).filter(\.isCore)
    }

    public func getTopic(projectId: UUID, named name: String) async throws -> KnowledgeTopic? {
        let file = topicFileURL(for: projectId, topicName: name)
        guard let data = FileManager.default.contents(atPath: file.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KnowledgeTopic.self, from: data)
    }

    public func saveTopic(_ topic: KnowledgeTopic, projectId: UUID) async throws {
        let knowledgeDir = knowledgeDirectoryURL(for: projectId)
        try FileManager.default.createDirectory(at: knowledgeDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(topic)
        try data.write(to: topicFileURL(for: projectId, topicName: topic.name))
    }

    public func deleteTopic(projectId: UUID, topicId: UUID) async throws {
        let topics = try await listTopics(projectId: projectId)
        guard let topic = topics.first(where: { $0.id == topicId }) else { return }
        let file = topicFileURL(for: projectId, topicName: topic.name)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func addEntry(_ entry: KnowledgeEntry, toTopic topicName: String, projectId: UUID) async throws {
        var topic = try await getTopic(projectId: projectId, named: topicName) ?? KnowledgeTopic(name: topicName)
        topic.entries.append(entry)
        topic.updatedAt = Date()
        try await saveTopic(topic, projectId: projectId)
    }

    public func removeEntry(entryId: UUID, fromTopic topicName: String, projectId: UUID) async throws {
        guard var topic = try await getTopic(projectId: projectId, named: topicName) else { return }
        topic.entries.removeAll { $0.id == entryId }
        topic.updatedAt = Date()
        try await saveTopic(topic, projectId: projectId)
    }

    public func search(query: String, projectId: UUID) async throws -> [KnowledgeSearchResult] {
        let topics = try await listTopics(projectId: projectId)
        let lowercaseQuery = query.lowercased()
        var results: [KnowledgeSearchResult] = []

        for topic in topics {
            // トピック名マッチ
            let topicNameMatch = topic.name.lowercased().contains(lowercaseQuery)
            let summaryMatch = topic.summary.lowercased().contains(lowercaseQuery)

            for entry in topic.entries {
                let contentMatch = entry.content.lowercased().contains(lowercaseQuery)
                if contentMatch || topicNameMatch || summaryMatch {
                    let score: Double
                    if contentMatch && topicNameMatch {
                        score = 1.0
                    } else if contentMatch {
                        score = 0.8
                    } else {
                        score = 0.5
                    }
                    results.append(KnowledgeSearchResult(
                        topicName: topic.name,
                        entry: entry,
                        relevanceScore: score
                    ))
                }
            }
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Private

    private func knowledgeDirectoryURL(for projectId: UUID) -> URL {
        baseDirectory.appendingPathComponent(projectId.uuidString).appendingPathComponent("knowledge")
    }

    private func topicFileURL(for projectId: UUID, topicName: String) -> URL {
        let sanitized = sanitizeFileName(topicName)
        return knowledgeDirectoryURL(for: projectId).appendingPathComponent("\(sanitized).json")
    }

    /// トピック名をファイルシステム安全な名前に変換
    private func sanitizeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
