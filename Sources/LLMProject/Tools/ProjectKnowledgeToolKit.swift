import Foundation
import LLMClient
import LLMTool
import LLMMCP
import AgentCommunication

/// ナレッジ管理ツールキット
///
/// 6つのツールでトピック指向のナレッジ管理を提供する。
///
/// ## 提供されるツール
///
/// - `knowledge_list`: トピック一覧取得
/// - `knowledge_read`: 特定トピック読取
/// - `knowledge_search`: 横断検索
/// - `knowledge_save`: エントリ追加（トピック自動作成）
/// - `knowledge_remove`: エントリ削除
/// - `knowledge_set_core`: Core フラグ切替
public final class KnowledgeToolKit: ToolKit, @unchecked Sendable {
    public let name: String = "knowledge"

    private let store: any KnowledgeStore

    public init(store: any KnowledgeStore) {
        self.store = store
    }

    // MARK: - ToolKit

    public var tools: [any Tool] {
        [listTool, readTool, searchTool, saveTool, removeTool, setCoreTool]
    }

    // MARK: - Tool Definitions

    private var listTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_list",
            description: "List all knowledge topics. Returns topic names, summaries, entry counts, and whether each topic is marked as core (auto-injected into every session).",
            inputSchema: .object(properties: [:], required: []),
            annotations: ToolAnnotations(
                title: "List Knowledge Topics",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [store] _ in
            let topics = try await store.listTopics()
            let output = topics.map { topic in
                TopicSummary(
                    name: topic.name,
                    summary: topic.summary,
                    entryCount: topic.entries.count,
                    isCore: topic.isCore
                )
            }
            return try .encodable(output)
        }
    }

    private var readTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_read",
            description: "Read the full contents of a specific knowledge topic, including all entries.",
            inputSchema: .object(
                properties: [
                    "topic": .string(description: "Name of the topic to read")
                ],
                required: ["topic"]
            ),
            annotations: ToolAnnotations(
                title: "Read Knowledge Topic",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [store] data in
            let input = try JSONDecoder().decode(TopicInput.self, from: data)
            guard let topic = try await store.getTopic(named: input.topic) else {
                return .text("Topic '\(input.topic)' not found.")
            }
            return try .encodable(topic)
        }
    }

    private var searchTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_search",
            description: "Search across all knowledge topics for entries matching the query.",
            inputSchema: .object(
                properties: [
                    "query": .string(description: "Search query string")
                ],
                required: ["query"]
            ),
            annotations: ToolAnnotations(
                title: "Search Knowledge",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [store] data in
            let input = try JSONDecoder().decode(SearchInput.self, from: data)
            let results = try await store.search(query: input.query)
            if results.isEmpty {
                return .text("No results found for '\(input.query)'.")
            }
            return try .encodable(results)
        }
    }

    private var saveTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_save",
            description: "Save a knowledge entry to the internal knowledge base (not a file on the filesystem). If the topic doesn't exist, it will be created automatically. Use this to persist the assistant's own learnings: architectural decisions, user preferences, recurring patterns, or technical context that should be available in future sessions. When the user explicitly asks to save, create, or write a file, use write_file instead.",
            inputSchema: .object(
                properties: [
                    "topic": .string(description: "Topic name (e.g. 'architecture', 'user-preferences', 'debugging-notes')"),
                    "content": .string(description: "The knowledge entry content in Markdown"),
                    "summary": .string(description: "Brief summary of the topic (used when creating a new topic, ignored if topic already exists)")
                ],
                required: ["topic", "content"]
            ),
            annotations: ToolAnnotations(
                title: "Save Knowledge",
                readOnlyHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { [store] data in
            let input = try JSONDecoder().decode(SaveInput.self, from: data)
            let entry = KnowledgeEntry(content: input.content)

            // トピックが存在しない場合、summary を使って新規作成
            if try await store.getTopic(named: input.topic) == nil,
               let summary = input.summary {
                let topic = KnowledgeTopic(name: input.topic, summary: summary, entries: [entry])
                try await store.saveTopic(topic)
            } else {
                try await store.addEntry(entry, toTopic: input.topic)
            }

            return .text("Saved to topic '\(input.topic)'.")
        }
    }

    private var removeTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_remove",
            description: "Remove a specific knowledge entry from a topic by its ID.",
            inputSchema: .object(
                properties: [
                    "topic": .string(description: "Topic name"),
                    "entryId": .string(description: "UUID of the entry to remove")
                ],
                required: ["topic", "entryId"]
            ),
            annotations: ToolAnnotations(
                title: "Remove Knowledge Entry",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [store] data in
            let input = try JSONDecoder().decode(RemoveInput.self, from: data)
            guard let entryId = UUID(uuidString: input.entryId) else {
                return .error("Invalid entry ID: \(input.entryId)")
            }
            try await store.removeEntry(entryId: entryId, fromTopic: input.topic)
            return .text("Removed entry \(input.entryId) from topic '\(input.topic)'.")
        }
    }

    private var setCoreTool: BuiltInTool {
        BuiltInTool(
            name: "knowledge_set_core",
            description: "Toggle whether a topic is 'core'. Core topics are automatically injected into the system prompt at the start of every session, ensuring the LLM always has access to this knowledge without needing to use tools.",
            inputSchema: .object(
                properties: [
                    "topic": .string(description: "Topic name"),
                    "isCore": .boolean(description: "Whether this topic should be core (auto-injected)")
                ],
                required: ["topic", "isCore"]
            ),
            annotations: ToolAnnotations(
                title: "Set Core Flag",
                readOnlyHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [store] data in
            let input = try JSONDecoder().decode(SetCoreInput.self, from: data)
            guard var topic = try await store.getTopic(named: input.topic) else {
                return .error("Topic '\(input.topic)' not found.")
            }
            topic.isCore = input.isCore
            topic.updatedAt = Date()
            try await store.saveTopic(topic)
            let status = input.isCore ? "core (auto-injected)" : "non-core (tool-access only)"
            return .text("Topic '\(input.topic)' is now \(status).")
        }
    }
}

// MARK: - Input / Output Types

private struct TopicInput: Codable {
    let topic: String
}

private struct SearchInput: Codable {
    let query: String
}

private struct SaveInput: Codable {
    let topic: String
    let content: String
    let summary: String?
}

private struct RemoveInput: Codable {
    let topic: String
    let entryId: String
}

private struct SetCoreInput: Codable {
    let topic: String
    let isCore: Bool
}

private struct TopicSummary: Codable {
    let name: String
    let summary: String
    let entryCount: Int
    let isCore: Bool
}

// MARK: - ToolResult Extension

private extension ToolResult {
    static func encodable<T: Encodable>(_ value: T) throws -> ToolResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return .json(data)
    }
}
