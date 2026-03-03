import Foundation
import LLMClient
import LLMTool

// MARK: - A2AAgentTool

/// A2Aエージェントのスキルを表すツール
///
/// Toolプロトコルに準拠しており、通常のツールと同様に使用できます。
/// A2Aエージェントへのリクエスト転送を担当します。
public final class A2AAgentTool: Tool, @unchecked Sendable {
    // MARK: - Properties

    /// ツール名
    public let toolName: String

    /// ツールの説明
    public let toolDescription: String

    /// スキルID
    public let skillId: String

    /// エージェント名
    public let agentName: String

    /// 入力スキーマ
    public let inputSchema: JSONSchema

    /// 実行ハンドラー
    private let executeHandler: @Sendable (Data) async throws -> ToolResult

    // MARK: - Initialization

    /// A2AAgentToolを作成
    public init(
        name: String,
        description: String,
        skillId: String,
        agentName: String,
        executeHandler: @escaping @Sendable (Data) async throws -> ToolResult
    ) {
        self.toolName = name
        self.toolDescription = description
        self.skillId = skillId
        self.agentName = agentName
        self.inputSchema = .object(
            description: "Input for A2A agent skill",
            properties: [
                "message": .string(description: "Message to send to the agent"),
            ],
            required: ["message"]
        )
        self.executeHandler = executeHandler
    }

    // MARK: - Tool Protocol

    /// ツールを実行
    public func execute(with argumentsData: Data) async throws -> ToolResult {
        try await executeHandler(argumentsData)
    }
}

// MARK: - A2AAgentPlaceholder

/// A2Aエージェントのプレースホルダーツール
///
/// ToolSet構築時に使用される一時的なプレースホルダーです。
/// 実際のA2Aツールは `resolvingA2AAgents()` で取得されます。
public final class A2AAgentPlaceholder: Tool, @unchecked Sendable {
    /// ラップしているA2Aエージェント
    public let agent: any A2AAgentProtocol

    /// プレースホルダーであることを示すツール名
    public var toolName: String {
        "__a2a_placeholder_\(agent.agentName)"
    }

    public var toolDescription: String {
        "A2A Agent placeholder for \(agent.agentName)"
    }

    public var inputSchema: JSONSchema {
        .object(description: nil, properties: [:], required: [])
    }

    public init(agent: any A2AAgentProtocol) {
        self.agent = agent
    }

    /// プレースホルダーは直接実行できない
    public func execute(with argumentsData: Data) async throws -> ToolResult {
        throw A2AIntegrationError.placeholderCannotExecute(agentName: agent.agentName)
    }

    /// A2Aエージェントから実際のツールを取得
    public func resolveTools() async throws -> [A2AAgentTool] {
        try await agent.fetchTools()
    }
}

// MARK: - ToolSetBuilder A2A Extensions

extension ToolSetBuilder {
    /// A2AAgentProtocol準拠型を配列として構築
    public static func buildExpression(_ agent: some A2AAgentProtocol) -> [any Tool] {
        [A2AAgentPlaceholder(agent: agent)]
    }
}

// MARK: - ToolSet A2A Extensions

extension ToolSet {
    /// A2Aエージェントのプレースホルダーを実際のツールに解決
    ///
    /// ToolSetに含まれるA2Aエージェントプレースホルダーを、
    /// 実際のA2Aツールに置き換えた新しいToolSetを返します。
    ///
    /// - Returns: A2Aツールが解決されたToolSet
    /// - Throws: A2A接続エラーまたはツール取得エラー
    public func resolvingA2AAgents() async throws -> ToolSet {
        var resolvedTools: [any Tool] = []

        for tool in tools {
            if let placeholder = tool as? A2AAgentPlaceholder {
                let a2aTools = try await placeholder.resolveTools()
                resolvedTools.append(contentsOf: a2aTools)
            } else {
                resolvedTools.append(tool)
            }
        }

        return ToolSet(tools: resolvedTools)
    }

    /// A2Aエージェントのプレースホルダーが含まれているかどうか
    public var containsA2APlaceholders: Bool {
        tools.contains { $0 is A2AAgentPlaceholder }
    }

    /// A2Aエージェントのプレースホルダー一覧を取得
    public var a2aPlaceholders: [A2AAgentPlaceholder] {
        tools.compactMap { $0 as? A2AAgentPlaceholder }
    }
}
