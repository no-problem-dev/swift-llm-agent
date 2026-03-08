import Foundation
import LLMClient
import AgentCommunication

// MARK: - GroupAwareAgent Knowledge Integration

extension GroupAwareAgent {

    /// 所属グループのコアナレッジを PromptComponent 配列として取得
    ///
    /// Workspace にナレッジファクトリが設定されていない場合、
    /// またはグループにナレッジストアがない場合は空配列を返す。
    ///
    /// - Parameters:
    ///   - groupId: グループ ID
    ///   - assembler: ナレッジレンダリング設定（デフォルト: 4000 文字上限）
    /// - Returns: SystemPrompt に注入可能な PromptComponent 配列
    public func knowledgePromptComponents(
        forGroup groupId: String,
        assembler: GroupKnowledgeAssembler = GroupKnowledgeAssembler()
    ) async throws -> [PromptComponent] {
        guard let workspace = self.workspace else { return [] }
        guard let store = await workspace.knowledgeStore(
            forGroup: groupId,
            requestedBy: participantId
        ) else { return [] }
        return try await assembler.promptComponents(from: store, label: "group_knowledge")
    }

    /// 全所属グループのコアナレッジを PromptComponent 配列として取得
    ///
    /// 複数グループに所属している場合、グループ名をラベルに含める。
    ///
    /// - Parameter assembler: ナレッジレンダリング設定
    /// - Returns: SystemPrompt に注入可能な PromptComponent 配列
    public func allGroupKnowledgePromptComponents(
        assembler: GroupKnowledgeAssembler = GroupKnowledgeAssembler()
    ) async throws -> [PromptComponent] {
        let stores = await myKnowledgeStores()
        var components: [PromptComponent] = []

        for (groupId, store) in stores {
            let label = "group_knowledge(\(groupId))"
            let groupComponents = try await assembler.promptComponents(from: store, label: label)
            components.append(contentsOf: groupComponents)
        }

        return components
    }

    /// グローバルナレッジを PromptComponent 配列として取得
    ///
    /// Workspace にグローバルナレッジストアが設定されていない場合は空配列を返す。
    ///
    /// - Parameter assembler: ナレッジレンダリング設定
    /// - Returns: SystemPrompt に注入可能な PromptComponent 配列
    public func globalKnowledgePromptComponents(
        assembler: GroupKnowledgeAssembler = GroupKnowledgeAssembler()
    ) async throws -> [PromptComponent] {
        guard let store = await globalKnowledgeStore() else { return [] }
        return try await assembler.promptComponents(from: store, label: "workspace_knowledge")
    }
}
