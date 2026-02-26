import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - DelegateTaskTool

/// サブエージェントにタスクを委譲するツール
///
/// LLM がプロンプトを書いてサブエージェントにタスクを委譲できます。
/// `agent_type` でカタログからサブエージェントの権限セットを選択し、
/// `prompt` でタスク内容を自由に記述します。
///
/// ## 使用例
///
/// ```swift
/// let catalog = SubAgentCatalogDefinition {
///     SubAgentTypeDefinition(
///         name: "researcher",
///         description: "Web search and information synthesis",
///         tools: ToolSet { WebSearchTool(); FetchTool() },
///         configuration: AgentConfiguration(maxSteps: 12)
///     )
/// }
///
/// let delegateTool = DelegateTaskTool(
///     client: anthropicClient,
///     model: .haiku,
///     catalog: catalog,
///     timeout: .seconds(120)
/// )
///
/// // 親エージェントの ToolSet に追加
/// let parentTools = ToolSet {
///     delegateTool
///     CalculatorTool()
/// }
/// ```
public struct DelegateTaskTool<Client: AgentCapableClient>: Tool
    where Client.Model: Sendable
{
    private let client: Client
    private let model: Client.Model
    private let catalog: any SubAgentCatalog
    private let timeout: Duration?
    private let eventHandler: SubAgentEventHandler?
    private let backgroundTaskRegistry: BackgroundTaskRegistry?

    // MARK: - Initialization

    /// DelegateTaskTool を初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - model: サブエージェントが使用するモデル
    ///   - catalog: サブエージェントタイプのカタログ
    ///   - timeout: タイムアウト（オプション）
    ///   - eventHandler: イベントハンドラー（オプション）
    ///   - backgroundTaskRegistry: バックグラウンドタスクレジストリ（nil の場合バックグラウンド実行無効）
    public init(
        client: Client,
        model: Client.Model,
        catalog: any SubAgentCatalog,
        timeout: Duration? = nil,
        eventHandler: SubAgentEventHandler? = nil,
        backgroundTaskRegistry: BackgroundTaskRegistry? = nil
    ) {
        self.client = client
        self.model = model
        self.catalog = catalog
        self.timeout = timeout
        self.eventHandler = eventHandler
        self.backgroundTaskRegistry = backgroundTaskRegistry
    }

    // MARK: - Tool Protocol

    public var toolName: String { "delegate_task" }

    public var toolDescription: String {
        var desc = "Delegate a task to a specialized sub-agent. "
            + "Choose an agent_type from the available types and provide a detailed prompt "
            + "describing what the sub-agent should do.\n\n"

        if backgroundTaskRegistry != nil {
            desc += "Set run_in_background to true to run the task in the background. "
                + "Use the task_output tool to retrieve results later.\n\n"
        }

        desc += "Available agent types:\n"

        for agentType in catalog.agentTypes {
            desc += "- \"\(agentType.name)\": \(agentType.description)\n"
        }

        return desc
    }

    public var inputSchema: JSONSchema {
        var properties: [String: JSONSchema] = [
            "prompt": .string(
                description: "Detailed instructions for the sub-agent. "
                    + "Be specific about what you want the sub-agent to accomplish."
            ),
            "description": .string(
                description: "A short (3-5 word) description of the task for logging purposes."
            ),
            "agent_type": .enum(
                catalog.agentTypeNames,
                description: "The type of sub-agent to use. "
                    + "Each type has different tools and capabilities."
            ),
        ]

        if backgroundTaskRegistry != nil {
            properties["run_in_background"] = .boolean(
                description: "Set to true to run the task in the background. "
                    + "The tool will return immediately with a task_id. "
                    + "Use the task_output tool to retrieve the result later."
            )
        }

        return .object(
            properties: properties,
            required: ["prompt", "description", "agent_type"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        // 引数デコード
        let args: Arguments
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            args = try decoder.decode(Arguments.self, from: argumentsData)
        } catch {
            return .error("Failed to decode arguments: \(error.localizedDescription)")
        }

        // カタログからエージェントタイプを検索
        guard let agentType = catalog.agentType(named: args.agentType) else {
            return .error(
                "Unknown agent type: \"\(args.agentType)\". "
                + "Available types: \(catalog.agentTypeNames.joined(separator: ", "))"
            )
        }

        // タスク識別子を生成（並列実行時のイベント識別用）
        let taskId = UUID()

        // バックグラウンド実行
        if args.runInBackground == true, let registry = backgroundTaskRegistry {
            await eventHandler?(
                .backgroundTaskRegistered(
                    taskId: taskId,
                    agentType: args.agentType,
                    description: args.description
                )
            )

            let taskHandle = Task<Void, Never> {
                do {
                    let result = try await SubAgentRunner.run(
                        client: self.client,
                        model: self.model,
                        prompt: args.prompt,
                        tools: agentType.tools,
                        systemPrompt: agentType.systemPrompt,
                        configuration: agentType.configuration,
                        timeout: self.timeout,
                        taskId: taskId,
                        eventHandler: self.eventHandler
                    )
                    await registry.markCompleted(taskId: taskId, result: result)
                    await self.eventHandler?(.completed(taskId: taskId, result: result))
                } catch {
                    let message = error.localizedDescription
                    await registry.markFailed(taskId: taskId, error: message)
                    await self.eventHandler?(.failed(taskId: taskId, error: error))
                }
            }

            await registry.register(
                taskId: taskId,
                agentType: args.agentType,
                description: args.description,
                taskHandle: taskHandle
            )

            return .text("Background task started. task_id: \(taskId.uuidString)")
        }

        // フォアグラウンド実行（既存パス）
        await eventHandler?(.started(taskId: taskId, agentType: args.agentType, description: args.description))

        do {
            let result = try await SubAgentRunner.run(
                client: client,
                model: model,
                prompt: args.prompt,
                tools: agentType.tools,
                systemPrompt: agentType.systemPrompt,
                configuration: agentType.configuration,
                timeout: timeout,
                taskId: taskId,
                eventHandler: eventHandler
            )
            return .text(result)
        } catch {
            await eventHandler?(.failed(taskId: taskId, error: error))
            return .error("Sub-agent failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Arguments

extension DelegateTaskTool {
    private struct Arguments: Decodable {
        let prompt: String
        let description: String
        let agentType: String
        let runInBackground: Bool?
    }
}
