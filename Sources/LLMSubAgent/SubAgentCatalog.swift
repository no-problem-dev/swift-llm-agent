import Foundation

// MARK: - SubAgentCatalog

/// サブエージェントタイプのカタログ
///
/// 利用可能なサブエージェントタイプを管理します。
/// `DelegateTaskTool` のコンストラクタに渡して使用します。
///
/// ## 使用例
///
/// ```swift
/// let catalog = SubAgentCatalogDefinition {
///     SubAgentTypeDefinition(
///         name: "researcher",
///         description: "Web search and information synthesis",
///         tools: ToolSet { WebSearchTool() }
///     )
///     SubAgentTypeDefinition(
///         name: "lightweight",
///         description: "Text generation only",
///         tools: ToolSet {}
///     )
/// }
///
/// catalog.agentType(named: "researcher") // SubAgentTypeDefinition?
/// catalog.agentTypeNames // ["researcher", "lightweight"]
/// ```
public protocol SubAgentCatalog: Sendable {
    /// 登録されたサブエージェントタイプの一覧
    var agentTypes: [any SubAgentType] { get }
}

// MARK: - Default Implementation

extension SubAgentCatalog {
    /// 名前でサブエージェントタイプを検索
    ///
    /// - Parameter name: 検索するタイプ名
    /// - Returns: 見つかったサブエージェントタイプ、なければ nil
    public func agentType(named name: String) -> (any SubAgentType)? {
        agentTypes.first { $0.name == name }
    }

    /// 登録されたサブエージェントタイプ名の一覧
    public var agentTypeNames: [String] {
        agentTypes.map { $0.name }
    }
}

// MARK: - SubAgentCatalogDefinition

/// サブエージェントカタログの具象定義
///
/// Result Builder を使用して宣言的にカタログを構築できます。
///
/// ## 使用例
///
/// ```swift
/// let catalog = SubAgentCatalogDefinition {
///     SubAgentTypeDefinition(name: "researcher", description: "Research agent")
///     SubAgentTypeDefinition(name: "writer", description: "Writing agent")
/// }
/// ```
public struct SubAgentCatalogDefinition: SubAgentCatalog {
    public let agentTypes: [any SubAgentType]

    /// Result Builder でカタログを構築
    ///
    /// - Parameter builder: サブエージェントタイプを構築するクロージャ
    public init(@SubAgentCatalogBuilder _ builder: () -> [any SubAgentType]) {
        self.agentTypes = builder()
    }

    /// 配列から直接初期化
    ///
    /// - Parameter agentTypes: サブエージェントタイプの配列
    public init(agentTypes: [any SubAgentType]) {
        self.agentTypes = agentTypes
    }
}

// MARK: - SubAgentCatalogBuilder

/// サブエージェントカタログ構築用の Result Builder
///
/// `ToolSetBuilder` と同じパターンで、条件分岐やループをサポートします。
///
/// ## 使用例
///
/// ```swift
/// let catalog = SubAgentCatalogDefinition {
///     SubAgentTypeDefinition(name: "a", description: "Agent A")
///
///     if enableResearch {
///         SubAgentTypeDefinition(name: "b", description: "Agent B")
///     }
/// }
/// ```
@resultBuilder
public struct SubAgentCatalogBuilder {

    public static func buildBlock(_ types: [any SubAgentType]...) -> [any SubAgentType] {
        types.flatMap { $0 }
    }

    public static func buildExpression(_ type: some SubAgentType) -> [any SubAgentType] {
        [type]
    }

    public static func buildExpression(_ types: [any SubAgentType]) -> [any SubAgentType] {
        types
    }

    public static func buildOptional(_ types: [any SubAgentType]?) -> [any SubAgentType] {
        types ?? []
    }

    public static func buildEither(first types: [any SubAgentType]) -> [any SubAgentType] {
        types
    }

    public static func buildEither(second types: [any SubAgentType]) -> [any SubAgentType] {
        types
    }

    public static func buildArray(_ types: [[any SubAgentType]]) -> [any SubAgentType] {
        types.flatMap { $0 }
    }

    public static func buildFinalResult(_ types: [any SubAgentType]) -> [any SubAgentType] {
        types
    }

    public static func buildLimitedAvailability(_ types: [any SubAgentType]) -> [any SubAgentType] {
        types
    }
}
