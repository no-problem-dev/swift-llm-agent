import Foundation
import LLMClient
import LLMTool
import LLMAgent
import LLMAgentSession
import LLMMCP

/// プロジェクトコンテキストを TurnConfiguration に合成するアセンブラ
///
/// 以下を自動で行う:
/// 1. project instructions を SystemPrompt 先頭に注入
/// 2. core knowledge を SystemPrompt に注入（`coreAlways` ポリシー時）
/// 3. `ProjectKnowledgeToolKit` をツールセットに自動追加
/// 4. LLM にナレッジ管理を指示する behavior プロンプトを注入
public struct ProjectContextAssembler: Sendable {
    let knowledgeStore: any ProjectKnowledgeStore

    /// Core ナレッジのシステムプロンプト注入文字数上限
    public var coreKnowledgeCharacterLimit: Int

    public init(
        knowledgeStore: any ProjectKnowledgeStore,
        coreKnowledgeCharacterLimit: Int = 4000
    ) {
        self.knowledgeStore = knowledgeStore
        self.coreKnowledgeCharacterLimit = coreKnowledgeCharacterLimit
    }

    /// TurnConfiguration にプロジェクトコンテキストを完全適用
    public func apply(
        _ project: Project,
        to config: TurnConfiguration,
        workspacePath: String? = nil
    ) async throws -> TurnConfiguration {
        var result = config

        // 1. SystemPrompt の合成
        result.systemPrompt = try await assembleSystemPrompt(
            project: project,
            existingPrompt: config.systemPrompt,
            workspacePath: workspacePath
        )

        // 2. ToolSet にナレッジツールを追加
        let toolKit = ProjectKnowledgeToolKit(store: knowledgeStore, projectId: project.id)
        result.tools = config.tools + toolKit

        return result
    }

    // MARK: - Private

    private func assembleSystemPrompt(
        project: Project,
        existingPrompt: SystemPrompt?,
        workspacePath: String?
    ) async throws -> SystemPrompt {
        var components: [PromptComponent] = []

        // 1. Workspace context（ワークスペースのパスとライフサイクルを LLM に伝える）
        if let workspacePath {
            components.append(.context("""
                You are working in project "\(project.name)".
                Working directory: \(workspacePath)
                Files saved here persist across all sessions in this project \
                and are visible to the user in the Files app.
                Save important results, artifacts, and generated content directly \
                to this directory using file tools.
                """))
        }

        // 2. Project Instructions（人間が書いたカスタム指示）
        let instructions = project.configuration.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            components.append(.context("project_instructions:\n\(instructions)"))
        }

        // 3. Core Knowledge（coreAlways ポリシーの場合）
        if project.configuration.knowledgePolicy == .coreAlways {
            let coreKnowledge = try await renderCoreKnowledge(projectId: project.id)
            if !coreKnowledge.isEmpty {
                components.append(.context("project_knowledge:\n\(coreKnowledge)"))
            }
        }

        // 4. Behavior: ナレッジ管理指示
        components.append(.behavior(knowledgeManagementBehavior))

        // 4. 既存の SystemPrompt と結合
        let projectPrompt = SystemPrompt(components: components)
        if let existing = existingPrompt {
            return projectPrompt + existing
        } else {
            return projectPrompt
        }
    }

    private func renderCoreKnowledge(projectId: UUID) async throws -> String {
        let coreTopics = try await knowledgeStore.getCoreTopics(projectId: projectId)
        guard !coreTopics.isEmpty else { return "" }

        var lines: [String] = []
        var charCount = 0

        for topic in coreTopics {
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
                if charCount > coreKnowledgeCharacterLimit {
                    lines.append("- (truncated — use project_knowledge_read for full content)")
                    break
                }
                lines.append(entryLine)
            }

            if charCount > coreKnowledgeCharacterLimit { break }
        }

        return lines.joined(separator: "\n")
    }

    /// LLM にナレッジ管理を自律的に行わせる behavior プロンプト
    private var knowledgeManagementBehavior: String {
        """
        You have access to project knowledge tools (project_knowledge_*). \
        When you learn something important that should persist across sessions \
        — such as architectural decisions, user preferences, recurring patterns, \
        or technical context — save it using project_knowledge_save. \
        Organize knowledge into meaningful topics. Mark topics as 'core' if they \
        should be automatically loaded into every future session. \
        Do not ask the user before saving knowledge — use your judgment.
        """
    }
}

