import Foundation
import LLMClient
import LLMTool
import LLMAgent
import LLMSubAgent

// MARK: - SkillTool

/// スキルを呼び出すツール
///
/// LLM がレジストリ内のスキルを選択・実行するためのツールです。
/// プログレッシブ・ディスクロージャにより、ツール説明にはスキル名と
/// 短い説明のみが含まれ、完全な指示はスキル実行時に初めて読み込まれます。
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     AgentSkillDefinition(
///         name: "summarize",
///         description: "Summarizes text content",
///         executionMode: .inline,
///         instructions: "Create a concise summary..."
///     )
/// }
///
/// let skillTool = SkillTool(
///     client: anthropicClient,
///     model: .haiku,
///     registry: registry
/// )
///
/// let tools = ToolSet {
///     skillTool
///     CalculatorTool()
/// }
/// ```
public struct SkillTool<Client: AgentCapableClient>: Tool
    where Client.Model: Sendable
{
    private let client: Client
    private let modelResolver: ModelTierResolver<Client.Model>
    private let registry: any SkillRegistry
    private let toolPool: ToolSet
    private let taskService: SubAgentTaskService<Client>?

    // MARK: - Initialization

    /// SkillTool を初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント（fork モードで使用）
    ///   - modelResolver: モデルティアを具体的なモデルに解決するクロージャ（fork モードで使用）
    ///   - registry: スキルレジストリ
    ///   - toolPool: サブエージェントに提供可能なツールプール（allowedTools フィルタの対象）
    ///   - taskService: バックグラウンドタスク制御サービス（nil の場合、バックグラウンド実行なし）
    public init(
        client: Client,
        modelResolver: @escaping ModelTierResolver<Client.Model>,
        registry: any SkillRegistry,
        toolPool: ToolSet = ToolSet(),
        taskService: SubAgentTaskService<Client>? = nil
    ) {
        self.client = client
        self.modelResolver = modelResolver
        self.registry = registry
        self.toolPool = toolPool
        self.taskService = taskService
    }

    // MARK: - Tool Protocol

    public var toolName: String { "use_skill" }

    public var toolDescription: String {
        let invocableSkills = registry.modelInvocableSkills
        guard !invocableSkills.isEmpty else {
            return "No skills available."
        }

        var desc = "Invoke a specialized skill. "
            + "Only use this tool when a skill clearly matches the user's request. "
            + "If no skill is a good fit, respond directly without calling this tool.\n\n"

        if taskService != nil {
            desc += "Set run_in_background to true for long-running forked skills. "
                + "Use wait_task, resume_task, cancel_task, or list_tasks to control them later.\n\n"
        }

        desc += "Available skills:\n"
        for skill in invocableSkills {
            let mode = skill.executionMode == .fork ? " [fork]" : ""
            desc += "- \"\(skill.name)\": \(skill.description)\(mode)\n"
        }

        return desc
    }

    public var inputSchema: JSONSchema {
        let skillNames = registry.modelInvocableSkills.map(\.name)

        var properties: [String: JSONSchema] = [
            "skill_name": .enum(
                skillNames,
                description: "The skill to invoke."
            ),
            "argument": .string(
                description: "The request or input for the skill. "
                    + "Be specific about what you want the skill to accomplish."
            ),
            "timeout_seconds": .integer(
                description: "Wall-clock timeout in seconds for a forked skill (1-1800)."
            ),
            "max_steps": .integer(
                description: "Optional step budget override for a forked skill."
            ),
        ]

        if taskService != nil {
            properties["run_in_background"] = .boolean(
                description: "Set to true to run a forked skill in the background."
            )
            properties["max_attempts"] = .integer(
                description: "Maximum background attempts before the task becomes failed."
            )
            properties["await_timeout_seconds"] = .integer(
                description: "If set when running in background, wait this many seconds for a state change before returning."
            )
        }

        return .object(
            properties: properties,
            required: ["skill_name", "argument"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let args: Arguments
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            args = try decoder.decode(Arguments.self, from: argumentsData)
        } catch {
            return .error("Failed to decode arguments: \(error.localizedDescription)")
        }

        guard let skill = registry.skill(named: args.skillName) else {
            return .error(
                "Unknown skill: \"\(args.skillName)\". "
                + "Available: \(registry.skillNames.joined(separator: ", "))"
            )
        }

        switch skill.executionMode {
        case .inline:
            return executeInline(skill: skill, argument: args.argument)

        case .fork:
            let taskId = UUID()

            if args.runInBackground == true, let taskService {
                return await executeForkBackground(
                    skill: skill,
                    argument: args.argument,
                    taskId: taskId,
                    taskService: taskService,
                    args: args
                )
            }

            return await executeForkForeground(
                skill: skill,
                argument: args.argument,
                taskId: taskId,
                args: args
            )
        }
    }

    // MARK: - Inline Execution

    private func executeInline(skill: any AgentSkill, argument: String) -> ToolResult {
        let content = """
            <skill_instructions name="\(skill.name)">
            \(skill.instructions)
            </skill_instructions>

            <user_request>
            \(argument)
            </user_request>
            """
        return .text(content)
    }

    // MARK: - Forked Execution

    private func resolveTools(for skill: any AgentSkill) -> ToolSet {
        // スキルが直接ツールを持つ場合はそれを使用
        if !skill.tools.isEmpty {
            return skill.tools
        }

        // allowedTools でツールプールからフィルタ
        if let allowedNames = skill.allowedTools {
            let filtered = toolPool.tools.filter { tool in
                allowedNames.contains(tool.toolName)
            }
            return ToolSet(tools: filtered)
        }

        // 制限なし: ツールプール全体を使用
        return toolPool
    }

    private func resolveSystemPrompt(for skill: any AgentSkill) -> SystemPrompt {
        if let explicit = skill.systemPrompt {
            return explicit
        }
        return SystemPrompt(stringLiteral: skill.instructions)
    }

    private func executeForkForeground(
        skill: any AgentSkill,
        argument: String,
        taskId: UUID,
        args: Arguments
    ) async -> ToolResult {
        let model = modelResolver(skill.modelTier)
        let configuration = applyMaxStepsOverride(args.maxSteps, to: skill.configuration)
        let timeout = parsedTimeout(args.timeoutSeconds)

        do {
            if let taskService {
                let result = try await taskService.runForeground(
                    agentType: "skill:\(skill.name)",
                    description: argument,
                    prompt: argument,
                    model: model,
                    tools: resolveTools(for: skill),
                    systemPrompt: resolveSystemPrompt(for: skill),
                    configuration: configuration,
                    timeout: timeout
                )
                return .text(result)
            }

            let result = try await SubAgentRunner.run(
                client: client,
                model: model,
                messages: [.user(argument)],
                tools: resolveTools(for: skill),
                systemPrompt: resolveSystemPrompt(for: skill),
                configuration: configuration,
                timeout: timeout,
                taskId: taskId,
                eventHandler: nil
            )
            return .text(result.output)
        } catch {
            return .error("Skill execution failed: \(error.localizedDescription)")
        }
    }

    private func executeForkBackground(
        skill: any AgentSkill,
        argument: String,
        taskId: UUID,
        taskService: SubAgentTaskService<Client>,
        args: Arguments
    ) async -> ToolResult {
        let model = modelResolver(skill.modelTier)
        let info = await taskService.startTask(
            agentType: "skill:\(skill.name)",
            description: argument,
            prompt: argument,
            model: model,
            tools: resolveTools(for: skill),
            systemPrompt: resolveSystemPrompt(for: skill),
            configuration: skill.configuration,
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
}

// MARK: - Arguments

extension SkillTool {
    private struct Arguments: Decodable {
        let skillName: String
        let argument: String
        let runInBackground: Bool?
        let timeoutSeconds: Int?
        let maxSteps: Int?
        let maxAttempts: Int?
        let awaitTimeoutSeconds: Int?
    }
}

private extension SkillTool {
    func parsedTimeout(_ timeoutSeconds: Int?) -> Duration? {
        guard let timeoutSeconds, timeoutSeconds > 0 else { return nil }
        return .seconds(min(timeoutSeconds, 1800))
    }

    func applyMaxStepsOverride(_ maxSteps: Int?, to configuration: AgentConfiguration) -> AgentConfiguration {
        guard let maxSteps, maxSteps > 0 else { return configuration }
        return AgentConfiguration(
            maxSteps: maxSteps,
            softMaxSteps: max(1, maxSteps - 2),
            autoExecuteTools: configuration.autoExecuteTools,
            maxDuplicateToolCalls: configuration.maxDuplicateToolCalls,
            maxToolCallsPerTool: configuration.maxToolCallsPerTool,
            maxInteractiveCalls: configuration.maxInteractiveCalls,
            thinkingMode: configuration.thinkingMode,
            skipFinalOutput: configuration.skipFinalOutput
        )
    }

    func renderTaskInfo(_ info: SubAgentTaskInfo) -> String {
        var lines = [
            "task_id: \(info.id.uuidString)",
            "agent_type: \(info.agentType)",
            "description: \(info.description)",
            "attempt: \(info.attempt)/\(info.maxAttempts)",
        ]

        switch info.status {
        case .queued:
            lines.append("status: queued")
        case .running:
            lines.append("status: running")
        case .paused(let reason, let note):
            lines.append("status: paused")
            lines.append("pause_reason: \(reason.rawValue)")
            lines.append("note: \(note)")
        case .completed(let result):
            lines.append("status: completed")
            lines.append("result: \(result)")
        case .failed(let message):
            lines.append("status: failed")
            lines.append("error: \(message)")
        case .cancelled:
            lines.append("status: cancelled")
        }

        return lines.joined(separator: "\n")
    }
}
