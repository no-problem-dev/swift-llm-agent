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
///     var systemPrompt: Prompt? { nil }
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

    /// システムプロンプト（オプション）
    var systemPrompt: Prompt? { get }

    /// エージェント設定
    var configuration: AgentConfiguration { get }
}

// MARK: - Default Implementation

extension SubAgentType {
    /// デフォルトのシステムプロンプト（nil）
    public var systemPrompt: Prompt? { nil }

    /// デフォルトのエージェント設定
    public var configuration: AgentConfiguration { .default }
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
    public let tools: ToolSet
    public let systemPrompt: Prompt?
    public let configuration: AgentConfiguration

    /// SubAgentTypeDefinition を初期化
    ///
    /// - Parameters:
    ///   - name: カタログ内の識別子
    ///   - description: LLM に見せる能力説明
    ///   - tools: 使用可能ツール
    ///   - systemPrompt: システムプロンプト（オプション）
    ///   - configuration: エージェント設定
    public init(
        name: String,
        description: String,
        tools: ToolSet = ToolSet {},
        systemPrompt: Prompt? = nil,
        configuration: AgentConfiguration = .default
    ) {
        self.name = name
        self.description = description
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.configuration = configuration
    }
}
