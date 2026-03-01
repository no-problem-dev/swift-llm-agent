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
    private let modelResolver: ModelTierResolver<Client.Model>
    private let catalog: any SubAgentCatalog
    private let taskService: SubAgentTaskService<Client>?

    // MARK: - Initialization

    /// DelegateTaskTool を初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント
    ///   - modelResolver: モデルティアを具体的なモデルに解決するクロージャ
    ///   - catalog: サブエージェントタイプのカタログ
    ///   - taskService: バックグラウンドタスク制御サービス（nil の場合、バックグラウンド実行なし）
    public init(
        client: Client,
        modelResolver: @escaping ModelTierResolver<Client.Model>,
        catalog: any SubAgentCatalog,
        taskService: SubAgentTaskService<Client>? = nil
    ) {
        self.client = client
        self.modelResolver = modelResolver
        self.catalog = catalog
        self.taskService = taskService
    }

    // MARK: - Tool Protocol

    public var toolName: String { "delegate_task" }

    public var toolDescription: String {
        var desc = "Delegate a task to a specialized sub-agent. "
            + "Choose an agent_type from the available types and provide a detailed prompt "
            + "describing what the sub-agent should do.\n\n"

        if taskService != nil {
            desc += "Set run_in_background to true to run the task in the background. "
                + "Use wait_task, resume_task, cancel_task, or list_tasks to control it later.\n\n"
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
            "timeout_seconds": .integer(
                description: "Wall-clock timeout in seconds for the delegated task (1-1800)."
            ),
            "max_steps": .integer(
                description: "Optional step budget override for the delegated task."
            ),
        ]

        if taskService != nil {
            properties["run_in_background"] = .boolean(
                description: "Set to true to run the task in the background. "
                    + "The tool will return immediately with a task_id. "
                    + "Use task control tools to inspect or resume it later."
            )
            properties["max_attempts"] = .integer(
                description: "Maximum number of background attempts before the task becomes failed."
            )
            properties["await_timeout_seconds"] = .integer(
                description: "If set when running in background, wait this many seconds for a state change before returning."
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

        // モデルティアに基づいてモデルを解決
        let model = modelResolver(agentType.modelTier)

        // バックグラウンド実行
        if args.runInBackground == true, let taskService {
            let info = await taskService.startTask(
                agentType: args.agentType,
                description: args.description,
                prompt: args.prompt,
                model: model,
                tools: agentType.tools,
                systemPrompt: agentType.systemPrompt,
                configuration: agentType.configuration,
                timeout: parsedTimeout(args.timeoutSeconds),
                maxStepsOverride: args.maxSteps,
                maxAttempts: args.maxAttempts ?? 2
            )

            if let awaitTimeout = args.awaitTimeoutSeconds, awaitTimeout > 0,
               let updated = await taskService.waitForTask(
                   id: info.id,
                   timeout: .seconds(min(awaitTimeout, 300))
               ) {
                return .text(renderTaskInfo(updated))
            }

            return .text(renderTaskInfo(info))
        }

        // フォアグラウンド実行
        do {
            let result: String
            if let taskService {
                result = try await taskService.runForeground(
                    agentType: args.agentType,
                    description: args.description,
                    prompt: args.prompt,
                    model: model,
                    tools: agentType.tools,
                    systemPrompt: agentType.systemPrompt,
                    configuration: applyMaxStepsOverride(args.maxSteps, to: agentType.configuration),
                    timeout: parsedTimeout(args.timeoutSeconds)
                )
            } else {
                let run = try await SubAgentRunner.run(
                    client: client,
                    model: model,
                    messages: [.user(args.prompt)],
                    tools: agentType.tools,
                    systemPrompt: agentType.systemPrompt,
                    configuration: applyMaxStepsOverride(args.maxSteps, to: agentType.configuration),
                    timeout: parsedTimeout(args.timeoutSeconds),
                    taskId: taskId,
                    eventHandler: nil
                )
                result = run.output
            }
            return .text(result)
        } catch {
            return .error("Sub-agent failed: \(error.localizedDescription)")
        }
    }
}

private extension DelegateTaskTool {
    func parsedTimeout(_ timeoutSeconds: Int?) -> Duration? {
        SubAgentToolHelpers.parsedTimeout(timeoutSeconds)
    }

    func applyMaxStepsOverride(_ maxSteps: Int?, to configuration: AgentConfiguration) -> AgentConfiguration {
        SubAgentToolHelpers.applyMaxStepsOverride(maxSteps, to: configuration)
    }

    func renderTaskInfo(_ info: SubAgentTaskInfo) -> String {
        SubAgentToolHelpers.renderTaskInfo(info)
    }
}

// MARK: - Arguments

extension DelegateTaskTool {
    private struct Arguments: Decodable {
        let prompt: String
        let description: String
        let agentType: String
        let runInBackground: Bool?
        let timeoutSeconds: Int?
        let maxSteps: Int?
        let maxAttempts: Int?
        let awaitTimeoutSeconds: Int?
    }
}
