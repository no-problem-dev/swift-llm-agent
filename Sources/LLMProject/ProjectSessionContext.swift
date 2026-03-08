import Foundation
import LLMClient
import LLMTool
import LLMAgent
import LLMAgentSession
import AgentCommunication

/// プロジェクトセッションコンテキスト — 便利な束ね型
///
/// `Project` と `ProjectContextAssembler` を束ね、
/// `TurnConfiguration` への適用を簡潔にする。
///
/// ## 使用例
///
/// ```swift
/// let context = ProjectSessionContext(
///     project: project,
///     knowledgeStore: knowledgeStore
/// )
///
/// let baseTurnConfig = TurnConfiguration(
///     systemPrompt: SystemPromptCatalog.researcher,
///     tools: ToolSet { WebSearchToolKit() }
/// )
///
/// // instructions, core knowledge, ナレッジツール, behavior がすべて自動追加
/// let turnConfig = try await context.apply(to: baseTurnConfig)
/// ```
public struct ProjectSessionContext: Sendable {
    public let project: Project
    public let assembler: ProjectContextAssembler
    public let workspacePath: String?

    public init(project: Project, knowledgeStore: any KnowledgeStore, workspacePath: String? = nil) {
        self.project = project
        self.assembler = ProjectContextAssembler(knowledgeStore: knowledgeStore)
        self.workspacePath = workspacePath
    }

    public init(
        project: Project,
        knowledgeStore: any KnowledgeStore,
        coreKnowledgeCharacterLimit: Int,
        workspacePath: String? = nil
    ) {
        self.project = project
        self.assembler = ProjectContextAssembler(
            knowledgeStore: knowledgeStore,
            coreKnowledgeCharacterLimit: coreKnowledgeCharacterLimit
        )
        self.workspacePath = workspacePath
    }

    /// TurnConfiguration にプロジェクトコンテキストを完全適用
    ///
    /// MCP/A2A プレースホルダー解決は行わない。
    /// アプリ層で apply 後に別途解決すること。
    public func apply(to config: TurnConfiguration) async throws -> TurnConfiguration {
        try await assembler.apply(project, to: config, workspacePath: workspacePath)
    }
}
