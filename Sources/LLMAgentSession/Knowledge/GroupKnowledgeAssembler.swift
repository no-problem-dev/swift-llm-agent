import Foundation
import LLMClient
import AgentCommunication

/// グループスコープのナレッジをプロンプトコンポーネントにレンダリングするアセンブラ
///
/// `GroupAwareAgent` がメッセージ処理時に、所属グループのコアナレッジを
/// LLM コンテキストに注入するために使用する。
///
/// ## 使用例
///
/// ```swift
/// let assembler = GroupKnowledgeAssembler()
/// let components = try await assembler.promptComponents(from: store, label: "group_knowledge")
/// ```
public struct GroupKnowledgeAssembler: Sendable {

    /// コアナレッジの文字数上限
    public let characterLimit: Int

    public init(characterLimit: Int = 4000) {
        self.characterLimit = characterLimit
    }

    /// KnowledgeStore のコアトピックを PromptComponent 配列にレンダリング
    ///
    /// コアトピックが存在しない場合は空配列を返す。
    /// 文字数上限を超えた場合は truncated メッセージを付加する。
    ///
    /// - Parameters:
    ///   - store: ナレッジストア
    ///   - label: コンテキストラベル（例: `"group_knowledge"`, `"workspace_knowledge"`）
    /// - Returns: SystemPrompt に注入可能な PromptComponent 配列
    public func promptComponents(
        from store: any KnowledgeStore,
        label: String = "group_knowledge"
    ) async throws -> [PromptComponent] {
        let markdown = try await renderCoreKnowledge(from: store)
        guard !markdown.isEmpty else { return [] }
        return [.context("\(label):\n\(markdown)")]
    }

    /// コアナレッジを Markdown 文字列にレンダリング
    ///
    /// - Parameter store: ナレッジストア
    /// - Returns: コアトピックの Markdown 文字列。コアトピックがない場合は空文字列
    public func renderCoreKnowledge(from store: any KnowledgeStore) async throws -> String {
        let coreTopics = try await store.getCoreTopics()
        guard !coreTopics.isEmpty else { return "" }
        return renderTopics(coreTopics)
    }

    // MARK: - Private

    private func renderTopics(_ topics: [KnowledgeTopic]) -> String {
        var lines: [String] = []
        var charCount = 0

        for topic in topics {
            let header = "## \(topic.name)"
            if !topic.summary.isEmpty {
                lines.append(header)
                lines.append(topic.summary)
            } else {
                lines.append(header)
            }
            charCount += header.count + topic.summary.count

            for entry in topic.entries {
                let entryLine = "- \(entry.content)"
                charCount += entryLine.count
                if charCount > characterLimit {
                    lines.append("- (truncated — use knowledge_read for full content)")
                    break
                }
                lines.append(entryLine)
            }

            if charCount > characterLimit { break }
        }

        return lines.joined(separator: "\n")
    }
}
