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

    public init(
        instructions: String = "",
        defaultSkillName: String? = nil,
        defaultModelTier: ModelTier? = nil,
        knowledgePolicy: KnowledgeInjectionPolicy = .coreAlways
    ) {
        self.instructions = instructions
        self.defaultSkillName = defaultSkillName
        self.defaultModelTier = defaultModelTier
        self.knowledgePolicy = knowledgePolicy
    }
}

/// ナレッジ注入ポリシー
public enum KnowledgeInjectionPolicy: String, Sendable, Codable, CaseIterable {
    /// Core ナレッジを常にシステムプロンプトに含める（デフォルト）
    case coreAlways
    /// すべてのナレッジをツール経由でのみ取得（コンテキスト節約）
    case toolOnly
}
