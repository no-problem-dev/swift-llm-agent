import A2UICore
import A2UIParser
import A2UIPrompt
import LLMAgent
import LLMClient
import LLMTool

extension AgentCapableClient {

    /// A2UI プロトコルに準拠したエージェントループを実行する。
    ///
    /// LLM の応答テキストから `<a2ui-json>` ブロックを自動抽出し、
    /// `A2UIResponsePart` として yield する。
    ///
    /// パースに失敗した場合、エラー内容を LLM にフィードバックして再生成を要求する。
    /// 最大リトライ回数は `a2uiConfiguration.maxParseRetries` で制御（デフォルト 2）。
    ///
    /// システムプロンプトは `promptConfiguration` から組み立てる。カスタムカタログを使う場合は
    /// `A2UIPromptConfiguration(promptBuilder:)` にカタログ schema を注入した builder を渡す。
    public func runA2UIAgent(
        input: LLMInput,
        model: Model,
        tools: ToolSet,
        promptConfiguration: A2UIPromptConfiguration = .default,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) -> some A2UIAgentStepStream {
        runA2UIAgent(
            messages: [input.toLLMMessage()],
            model: model,
            tools: tools,
            promptConfiguration: promptConfiguration,
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration
        )
    }

    /// 会話履歴を渡すバリアント。
    public func runA2UIAgent(
        messages: [LLMMessage],
        model: Model,
        tools: ToolSet,
        promptConfiguration: A2UIPromptConfiguration = .default,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) -> some A2UIAgentStepStream {
        A2UIAgentStepSequence(
            client: self,
            model: model,
            initialMessages: messages,
            tools: tools,
            systemPrompt: promptConfiguration.makeSystemPrompt(),
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration
        )
    }

    // MARK: - Convenience (role-only)

    /// 役割文だけを差し替える簡易版（basic カタログ前提）。
    public func runA2UIAgent(
        input: LLMInput,
        model: Model,
        tools: ToolSet,
        role: String,
        additionalSystemPrompt: SystemPrompt? = nil,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) -> some A2UIAgentStepStream {
        runA2UIAgent(
            messages: [input.toLLMMessage()],
            model: model,
            tools: tools,
            promptConfiguration: A2UIPromptConfiguration(role: role, additionalSystemPrompt: additionalSystemPrompt),
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration
        )
    }
}
