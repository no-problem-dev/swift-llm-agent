import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - SkillInvocationMode

/// スキル呼び出しの許可モード
public enum SkillInvocationMode: Sendable, Equatable, Codable {
    /// ユーザーとLLM双方が呼び出し可能
    case both
    /// LLM のみが自律的に呼び出し可能
    case modelOnly
    /// ユーザーのみが呼び出し可能
    case userOnly
    /// 誰も呼び出し不可（無効化）
    case none
}

// MARK: - SkillDisplayConfig

/// スキルの表示設定
public struct SkillDisplayConfig: Sendable {
    public let displayName: String?
    public let iconName: String
    public let category: String?
    public let displayOrder: Int

    public init(
        displayName: String? = nil,
        iconName: String = "sparkles",
        category: String? = nil,
        displayOrder: Int = 999
    ) {
        self.displayName = displayName
        self.iconName = iconName
        self.category = category
        self.displayOrder = displayOrder
    }
}

// MARK: - SkillExecutionConfig

/// スキルの実行設定
public struct SkillExecutionConfig: Sendable {
    public let executionMode: SkillExecutionMode
    public let modelTier: ModelTier
    public let configuration: AgentConfiguration
    public let isEphemeral: Bool

    public init(
        executionMode: SkillExecutionMode = .inline,
        modelTier: ModelTier = .standard,
        configuration: AgentConfiguration = .default,
        isEphemeral: Bool = false
    ) {
        self.executionMode = executionMode
        self.modelTier = modelTier
        self.configuration = configuration
        self.isEphemeral = isEphemeral
    }
}

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

    /// スキルの利用可能性（required = 常時有効, optional = 任意有効）
    ///
    /// `required`: レジストリに含まれる限り常に有効。UI でトグル不可。
    /// `optional`: デフォルト無効。ユーザーが明示的に有効化する。
    var availability: SkillAvailability { get }

    /// スキル呼び出しの許可モード（ユーザー/LLM/両方）
    var invocationMode: SkillInvocationMode { get }

    // MARK: - Optional (UI / Metadata)

    /// UI 表示用の名前（例: "朝のブリーフィング"）
    var displayName: String { get }

    /// SF Symbols アイコン名（例: "sun.horizon.fill"）
    var iconName: String { get }

    /// スキルの論理カテゴリ（例: "routine", "thinking"）
    var category: String? { get }

    /// 表示順序（小さいほど先頭）
    var displayOrder: Int { get }

    /// 引数のヒント（UI 表示用、例: "[URL or keyword]"）
    var argumentHint: String? { get }

    /// 補足メタデータ
    var metadata: SkillMetadata? { get }

    /// fork モードのサブエージェントが使用するモデルティア
    var modelTier: ModelTier { get }

    /// エフェメラルセッションとして実行するか
    ///
    /// `true` の場合、スキル起動時にセッションを永続化せず、
    /// 完了後にセッション一覧に残らない一時的なセッションとして動作する。
    var isEphemeral: Bool { get }
}

// MARK: - Default Implementations

extension AgentSkill {
    public var allowedTools: [String]? { nil }
    public var tools: ToolSet { ToolSet() }
    public var systemPrompt: SystemPrompt? { nil }
    public var configuration: AgentConfiguration { .default }
    public var availability: SkillAvailability { .required }
    public var invocationMode: SkillInvocationMode { .both }
    public var displayName: String { name }
    public var iconName: String { "sparkles" }
    public var category: String? { nil }
    public var displayOrder: Int { 999 }
    public var argumentHint: String? { nil }
    public var metadata: SkillMetadata? { nil }
    public var modelTier: ModelTier { .standard }
    public var isEphemeral: Bool { false }

    // MARK: - Derived Properties (from invocationMode)

    /// ユーザーが直接呼び出し可能か
    public var isUserInvocable: Bool {
        invocationMode == .both || invocationMode == .userOnly
    }

    /// LLM が自律的に呼び出し可能か
    public var isModelInvocable: Bool {
        invocationMode == .both || invocationMode == .modelOnly
    }
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
    public let availability: SkillAvailability
    public let displayName: String
    public let iconName: String
    public let category: String?
    public let displayOrder: Int
    public let invocationMode: SkillInvocationMode
    public let argumentHint: String?
    public let metadata: SkillMetadata?
    public let modelTier: ModelTier
    public let isEphemeral: Bool

    public init(
        name: String,
        description: String,
        executionMode: SkillExecutionMode = .inline,
        instructions: String,
        allowedTools: [String]? = nil,
        tools: ToolSet = ToolSet(),
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default,
        availability: SkillAvailability = .required,
        displayName: String? = nil,
        iconName: String = "sparkles",
        category: String? = nil,
        displayOrder: Int = 999,
        invocationMode: SkillInvocationMode = .both,
        argumentHint: String? = nil,
        metadata: SkillMetadata? = nil,
        modelTier: ModelTier = .standard,
        isEphemeral: Bool = false
    ) {
        self.name = name
        self.description = description
        self.executionMode = executionMode
        self.instructions = instructions
        self.allowedTools = allowedTools
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.configuration = configuration
        self.availability = availability
        self.displayName = displayName ?? name
        self.iconName = iconName
        self.category = category
        self.displayOrder = displayOrder
        self.invocationMode = invocationMode
        self.argumentHint = argumentHint
        self.metadata = metadata
        self.modelTier = modelTier
        self.isEphemeral = isEphemeral
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
        availability: SkillAvailability = .required,
        displayName: String? = nil,
        iconName: String = "sparkles",
        category: String? = nil,
        displayOrder: Int = 999,
        invocationMode: SkillInvocationMode = .both,
        argumentHint: String? = nil,
        metadata: SkillMetadata? = nil,
        modelTier: ModelTier = .standard,
        isEphemeral: Bool = false,
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
        self.availability = availability
        self.displayName = displayName ?? name
        self.iconName = iconName
        self.category = category
        self.displayOrder = displayOrder
        self.invocationMode = invocationMode
        self.argumentHint = argumentHint
        self.metadata = metadata
        self.modelTier = modelTier
        self.isEphemeral = isEphemeral
    }
}
