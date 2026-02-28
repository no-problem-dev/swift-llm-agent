import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - AgentSkill

/// Agent Skills 標準に準拠したスキルを定義するプロトコル
///
/// スキルは LLM エージェントに特定の能力を付与する再利用可能な指示セットです。
/// `inline` モードでは指示がコンテキストに注入され、
/// `fork` モードではサブエージェントに委譲されます。
///
/// ## 使用例
///
/// ```swift
/// struct CodeReviewSkill: AgentSkill {
///     var name: String { "code-review" }
///     var description: String { "Reviews code for quality and best practices" }
///     var executionMode: SkillExecutionMode { .fork }
///     var instructions: String {
///         """
///         When reviewing code, check for:
///         1. Correctness and logic errors
///         2. Security vulnerabilities
///         3. Performance concerns
///         """
///     }
///     var allowedTools: [String]? { ["read_file", "search_code"] }
/// }
/// ```
public protocol AgentSkill: Sendable {
    // MARK: - Required (Agent Skills Standard)

    /// スキルの識別子（SKILL.md の `name` フィールド）
    var name: String { get }

    /// LLM に見せる短い能力説明（SKILL.md の `description` フィールド）
    ///
    /// プログレッシブ・ディスクロージャにより、この説明のみが
    /// ツール定義に含まれます（~100 トークン）。
    var description: String { get }

    // MARK: - Required (Execution)

    /// 実行モード
    var executionMode: SkillExecutionMode { get }

    /// 完全な指示内容（SKILL.md のマークダウン本文）
    ///
    /// `inline`: ツール結果としてエージェントに返される
    /// `fork`: サブエージェントのシステムプロンプトになる
    ///
    /// スキル呼び出し時にのみ読み込まれる（プログレッシブ・ディスクロージャ）。
    var instructions: String { get }

    // MARK: - Optional (with defaults)

    /// 許可するツール名のリスト
    ///
    /// `fork` モード: サブエージェントが使用できるツールをこのリストに制限
    /// `inline` モード: アドバイザリー（フレームワークレベルでは非強制）
    /// `nil` の場合は制限なし
    var allowedTools: [String]? { get }

    /// スキル固有のツールセット
    ///
    /// `fork` モードのサブエージェントに直接付与するツール。
    /// `allowedTools` がフィルタリング、`tools` が直接指定。
    /// 空の場合はツールプールからフィルタリング。
    var tools: ToolSet { get }

    /// サブエージェント用のシステムプロンプト（fork モード用追加プロンプト）
    ///
    /// `nil` の場合、`instructions` がシステムプロンプトとして使用される
    var systemPrompt: SystemPrompt? { get }

    /// サブエージェントのエージェント設定（fork モード用）
    var configuration: AgentConfiguration { get }

    // MARK: - Optional (Invocation Control)

    /// ユーザーが直接呼び出し可能か（例: UI のコマンドリストに表示）
    var isUserInvocable: Bool { get }

    /// LLM が自律的に呼び出し可能か
    ///
    /// `false` の場合、ユーザーの明示的な指示がないと呼び出されない
    var isModelInvocable: Bool { get }

    // MARK: - Optional (UI / Metadata)

    /// 引数のヒント（UI 表示用、例: "[URL or keyword]"）
    var argumentHint: String? { get }

    /// 補足メタデータ
    var metadata: SkillMetadata? { get }

    /// fork モードのサブエージェントが使用するモデルティア
    var modelTier: ModelTier { get }
}

// MARK: - Default Implementations

extension AgentSkill {
    public var allowedTools: [String]? { nil }
    public var tools: ToolSet { ToolSet() }
    public var systemPrompt: SystemPrompt? { nil }
    public var configuration: AgentConfiguration { .default }
    public var isUserInvocable: Bool { true }
    public var isModelInvocable: Bool { true }
    public var argumentHint: String? { nil }
    public var metadata: SkillMetadata? { nil }
    public var modelTier: ModelTier { .standard }
}

// MARK: - AgentSkillDefinition

/// Agent Skill の具象定義
///
/// `AgentSkill` プロトコルの値型実装です。
/// コード定義や `SkillLoader` からの生成に使用されます。
///
/// ## 使用例
///
/// ```swift
/// let skill = AgentSkillDefinition(
///     name: "summarize",
///     description: "Summarizes text content",
///     executionMode: .inline,
///     instructions: "Read the provided text and create a concise summary..."
/// )
/// ```
public struct AgentSkillDefinition: AgentSkill {
    public let name: String
    public let description: String
    public let executionMode: SkillExecutionMode
    public let instructions: String
    public let allowedTools: [String]?
    public let tools: ToolSet
    public let systemPrompt: SystemPrompt?
    public let configuration: AgentConfiguration
    public let isUserInvocable: Bool
    public let isModelInvocable: Bool
    public let argumentHint: String?
    public let metadata: SkillMetadata?
    public let modelTier: ModelTier

    public init(
        name: String,
        description: String,
        executionMode: SkillExecutionMode = .inline,
        instructions: String,
        allowedTools: [String]? = nil,
        tools: ToolSet = ToolSet(),
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default,
        isUserInvocable: Bool = true,
        isModelInvocable: Bool = true,
        argumentHint: String? = nil,
        metadata: SkillMetadata? = nil,
        modelTier: ModelTier = .standard
    ) {
        self.name = name
        self.description = description
        self.executionMode = executionMode
        self.instructions = instructions
        self.allowedTools = allowedTools
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.configuration = configuration
        self.isUserInvocable = isUserInvocable
        self.isModelInvocable = isModelInvocable
        self.argumentHint = argumentHint
        self.metadata = metadata
        self.modelTier = modelTier
    }

    /// ToolSetBuilder クロージャで初期化
    ///
    /// ```swift
    /// let skill = AgentSkillDefinition(
    ///     name: "code-review",
    ///     description: "Reviews code for quality",
    ///     executionMode: .fork,
    ///     instructions: "Review the code..."
    /// ) {
    ///     ReadFileTool()
    ///     SearchCodeTool()
    /// }
    /// ```
    public init(
        name: String,
        description: String,
        executionMode: SkillExecutionMode = .inline,
        instructions: String,
        allowedTools: [String]? = nil,
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default,
        isUserInvocable: Bool = true,
        isModelInvocable: Bool = true,
        argumentHint: String? = nil,
        metadata: SkillMetadata? = nil,
        modelTier: ModelTier = .standard,
        @ToolSetBuilder tools: () -> [any Tool]
    ) {
        self.name = name
        self.description = description
        self.executionMode = executionMode
        self.instructions = instructions
        self.allowedTools = allowedTools
        self.tools = ToolSet(tools)
        self.systemPrompt = systemPrompt
        self.configuration = configuration
        self.isUserInvocable = isUserInvocable
        self.isModelInvocable = isModelInvocable
        self.argumentHint = argumentHint
        self.metadata = metadata
        self.modelTier = modelTier
    }
}
