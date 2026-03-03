import Foundation
import LLMAgent

/// プロジェクト設定 — 2層指示モデル
///
/// Claude Code の CLAUDE.md（人間記述）+ Auto Memory（LLM 自動記録）パターン。
public struct ProjectConfiguration: Sendable, Codable, Equatable {
    /// 人間が書くカスタム指示（CLAUDE.md / Claude Projects custom instructions 相当）
    ///
    /// セッション開始時に SystemPrompt の `<project_instructions>` ブロックとして注入される。
    public var instructions: String

    /// デフォルトスキル名
    public var defaultSkillName: String?

    /// デフォルトモデルティア
    public var defaultModelTier: ModelTier?

    /// ナレッジ注入ポリシー
    public var knowledgePolicy: KnowledgeInjectionPolicy

    /// プロジェクトにインストール済みのカタログスキル名
    public var installedCatalogSkillNames: Set<String>

    /// プロジェクトにインストール済みのカタログエージェント名
    public var installedCatalogAgentNames: Set<String>

    /// ツール設定の永続化用データ（AppPackage の ToolConfiguration を opaque Data として保持）
    public var toolConfigurationData: Data?

    public init(
        instructions: String = "",
        defaultSkillName: String? = nil,
        defaultModelTier: ModelTier? = nil,
        knowledgePolicy: KnowledgeInjectionPolicy = .coreAlways,
        installedCatalogSkillNames: Set<String> = [],
        installedCatalogAgentNames: Set<String> = [],
        toolConfigurationData: Data? = nil
    ) {
        self.instructions = instructions
        self.defaultSkillName = defaultSkillName
        self.defaultModelTier = defaultModelTier
        self.knowledgePolicy = knowledgePolicy
        self.installedCatalogSkillNames = installedCatalogSkillNames
        self.installedCatalogAgentNames = installedCatalogAgentNames
        self.toolConfigurationData = toolConfigurationData
    }
}

/// ナレッジ注入ポリシー
public enum KnowledgeInjectionPolicy: String, Sendable, Codable, CaseIterable {
    /// Core ナレッジを常にシステムプロンプトに含める（デフォルト）
    case coreAlways
    /// すべてのナレッジをツール経由でのみ取得（コンテキスト節約）
    case toolOnly
}
