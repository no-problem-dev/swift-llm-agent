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
    private let timeout: Duration?
    private let eventHandler: SubAgentEventHandler?
    private let backgroundTaskRegistry: BackgroundTaskRegistry?

    // MARK: - Initialization

    /// SkillTool を初期化
    ///
    /// - Parameters:
    ///   - client: LLM クライアント（fork モードで使用）
    ///   - modelResolver: モデルティアを具体的なモデルに解決するクロージャ（fork モードで使用）
    ///   - registry: スキルレジストリ
    ///   - toolPool: サブエージェントに提供可能なツールプール（allowedTools フィルタの対象）
    ///   - timeout: fork 実行のタイムアウト
    ///   - eventHandler: イベントハンドラー
    ///   - backgroundTaskRegistry: バックグラウンドタスクレジストリ（nil の場合バックグラウンド実行無効）
    public init(
        client: Client,
        modelResolver: @escaping ModelTierResolver<Client.Model>,
        registry: any SkillRegistry,
        toolPool: ToolSet = ToolSet(),
        timeout: Duration? = nil,
        eventHandler: SubAgentEventHandler? = nil,
        backgroundTaskRegistry: BackgroundTaskRegistry? = nil
    ) {
        self.client = client
        self.modelResolver = modelResolver
        self.registry = registry
        self.toolPool = toolPool
        self.timeout = timeout
        self.eventHandler = eventHandler
        self.backgroundTaskRegistry = backgroundTaskRegistry
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

        if backgroundTaskRegistry != nil {
            desc += "Set run_in_background to true for long-running forked skills. "
                + "Use the task_output tool to retrieve results later.\n\n"
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
        ]

        if backgroundTaskRegistry != nil {
            properties["run_in_background"] = .boolean(
                description: "Set to true to run a forked skill in the background."
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

            if args.runInBackground == true, let bgRegistry = backgroundTaskRegistry {
                return await executeForkBackground(
                    skill: skill,
                    argument: args.argument,
                    taskId: taskId,
                    backgroundRegistry: bgRegistry
                )
            }

            return await executeForkForeground(
                skill: skill,
                argument: args.argument,
                taskId: taskId
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
        taskId: UUID
    ) async -> ToolResult {
        await eventHandler?(
            .started(taskId: taskId, agentType: "skill:\(skill.name)", description: argument)
        )

        let model = modelResolver(skill.modelTier)

        do {
            let result = try await SubAgentRunner.run(
                client: client,
                model: model,
                prompt: argument,
                tools: resolveTools(for: skill),
                systemPrompt: resolveSystemPrompt(for: skill),
                configuration: skill.configuration,
                timeout: timeout,
                taskId: taskId,
                eventHandler: eventHandler
            )
            return .text(result)
        } catch {
            await eventHandler?(.failed(taskId: taskId, error: error))
            return .error("Skill execution failed: \(error.localizedDescription)")
        }
    }

    private func executeForkBackground(
        skill: any AgentSkill,
        argument: String,
        taskId: UUID,
        backgroundRegistry: BackgroundTaskRegistry
    ) async -> ToolResult {
        await eventHandler?(
            .backgroundTaskRegistered(
                taskId: taskId,
                agentType: "skill:\(skill.name)",
                description: argument
            )
        )

        let resolvedTools = resolveTools(for: skill)
        let resolvedPrompt = resolveSystemPrompt(for: skill)
        let backgroundConfig = skill.configuration.forBackground
        let model = modelResolver(skill.modelTier)

        let taskHandle = Task<Void, Never> {
            do {
                let result = try await SubAgentRunner.run(
                    client: self.client,
                    model: model,
                    prompt: argument,
                    tools: resolvedTools,
                    systemPrompt: resolvedPrompt,
                    configuration: backgroundConfig,
                    timeout: self.timeout,
                    taskId: taskId,
                    eventHandler: self.eventHandler
                )
                await backgroundRegistry.markCompleted(taskId: taskId, result: result)
                await self.eventHandler?(.completed(taskId: taskId, result: result))
            } catch {
                let message = error.localizedDescription
                await backgroundRegistry.markFailed(taskId: taskId, error: message)
                await self.eventHandler?(.failed(taskId: taskId, error: error))
            }
        }

        await backgroundRegistry.register(
            taskId: taskId,
            agentType: "skill:\(skill.name)",
            description: argument,
            taskHandle: taskHandle
        )

        return .text("Background skill started. task_id: \(taskId.uuidString)")
    }
}

// MARK: - Arguments

extension SkillTool {
    private struct Arguments: Decodable {
        let skillName: String
        let argument: String
        let runInBackground: Bool?
    }
}
