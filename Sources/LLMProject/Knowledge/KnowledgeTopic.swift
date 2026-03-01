import Foundation

/// トピック指向ナレッジ
///
/// Claude Code の MEMORY.md + トピックファイルパターンに倣う。
/// 各トピックは名前付きのエントリ集合で、`isCore` フラグにより
/// セッション開始時の自動注入を制御する。
public struct KnowledgeTopic: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var summary: String
    public var entries: [KnowledgeEntry]
    public var isCore: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        entries: [KnowledgeEntry] = [],
        isCore: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.entries = entries
        self.isCore = isCore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// ナレッジエントリ — トピック内の個別記録
public struct KnowledgeEntry: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public var content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

/// ナレッジ検索結果
public struct KnowledgeSearchResult: Sendable, Codable, Equatable {
    public let topicName: String
    public let entry: KnowledgeEntry
    public let relevanceScore: Double

    public init(topicName: String, entry: KnowledgeEntry, relevanceScore: Double = 1.0) {
        self.topicName = topicName
        self.entry = entry
        self.relevanceScore = relevanceScore
    }
}
