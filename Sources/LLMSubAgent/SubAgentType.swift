import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - SubAgentType

/// サブエージェントの種類を定義するプロトコル
///
/// 各サブエージェントタイプは、使用可能なツール、システムプロンプト、
/// 設定を持ちます。カタログに登録して `DelegateTaskTool` から利用されます。
///
/// ## 使用例
///
/// ```swift
/// struct ResearcherAgent: SubAgentType {
///     var name: String { "researcher" }
///     var description: String { "Web search and information synthesis" }
///     var tools: ToolSet { ToolSet { WebSearchTool(); FetchTool() } }
///     var systemPrompt: SystemPrompt? { nil }
///     var configuration: AgentConfiguration { AgentConfiguration(maxSteps: 12) }
/// }
/// ```
public protocol SubAgentType: Sendable {
    /// カタログ内の識別子
    var name: String { get }

    /// LLM に見せる能力説明
    var description: String { get }

    /// 使用可能ツール
    var tools: ToolSet { get }

    /// 許可するツール名のリスト
    ///
    /// `tools` が空の場合、このリストで toolPool からフィルタリング。
    /// `nil` の場合は制限なし。
    var allowedTools: [String]? { get }

    /// システムプロンプト（オプション）
    var systemPrompt: SystemPrompt? { get }

    /// エージェント設定
    var configuration: AgentConfiguration { get }

    /// モデルの強度ティア
    var modelTier: ModelTier { get }
}

// MARK: - Default Implementation

extension SubAgentType {
    /// デフォルトの allowedTools（nil = 制限なし）
    public var allowedTools: [String]? { nil }

    /// デフォルトのシステムプロンプト（nil）
    public var systemPrompt: SystemPrompt? { nil }

    /// デフォルトのエージェント設定
    public var configuration: AgentConfiguration { .default }

    /// デフォルトのモデルティア（standard）
    public var modelTier: ModelTier { .standard }
}

// MARK: - SubAgentTypeDefinition

/// サブエージェントタイプの具象定義
///
/// `SubAgentType` プロトコルの値型実装です。
/// カタログ構築時に直接使用できます。
///
/// ## 使用例
///
/// ```swift
/// let researcher = SubAgentTypeDefinition(
///     name: "researcher",
///     description: "Web search and information synthesis",
///     tools: ToolSet { WebSearchTool(); FetchTool() },
///     configuration: AgentConfiguration(maxSteps: 12)
/// )
/// ```
public struct SubAgentTypeDefinition: SubAgentType {
    public let name: String
    public let description: String
    public let displayName: String?
    public let iconName: String?
    public let tools: ToolSet
    public let allowedTools: [String]?
    public let systemPrompt: SystemPrompt?
    public let configuration: AgentConfiguration
    public let modelTier: ModelTier

    /// SubAgentTypeDefinition を初期化
    ///
    /// - Parameters:
    ///   - name: カタログ内の識別子
    ///   - description: LLM に見せる能力説明
    ///   - displayName: UI 表示用の名前（省略時は name を使用）
    ///   - iconName: SF Symbols アイコン名（省略時はデフォルトアイコン）
    ///   - tools: 使用可能ツール
    ///   - allowedTools: 許可するツール名のリスト（toolPool からフィルタ用）
    ///   - systemPrompt: システムプロンプト（オプション）
    ///   - configuration: エージェント設定
    ///   - modelTier: モデルの強度ティア
    public init(
        name: String,
        description: String,
        displayName: String? = nil,
        iconName: String? = nil,
        tools: ToolSet = ToolSet {},
        allowedTools: [String]? = nil,
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default,
        modelTier: ModelTier = .standard
    ) {
        self.name = name
        self.description = description
        self.displayName = displayName
        self.iconName = iconName
        self.tools = tools
        self.allowedTools = allowedTools
        self.systemPrompt = systemPrompt
        self.configuration = configuration
        self.modelTier = modelTier
    }

    /// ToolSetBuilder クロージャで初期化
    ///
    /// ```swift
    /// let researcher = SubAgentTypeDefinition(
    ///     name: "researcher",
    ///     description: "Web search and information synthesis"
    /// ) {
    ///     WebSearchTool()
    ///     FetchTool()
    /// }
    /// ```
    public init(
        name: String,
        description: String,
        displayName: String? = nil,
        iconName: String? = nil,
        allowedTools: [String]? = nil,
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default,
        modelTier: ModelTier = .standard,
        @ToolSetBuilder tools: () -> [any Tool]
    ) {
        self.name = name
        self.description = description
        self.displayName = displayName
        self.iconName = iconName
        self.tools = ToolSet(tools)
        self.allowedTools = allowedTools
        self.systemPrompt = systemPrompt
        self.configuration = configuration
        self.modelTier = modelTier
    }
}
