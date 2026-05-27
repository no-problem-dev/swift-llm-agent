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
    /// システムプロンプトには A2UI のスキーマとワークフロールールが自動注入される。
    public func runA2UIAgent(
        input: LLMInput,
        model: Model,
        tools: ToolSet,
        role: String = "You are a helpful assistant that generates A2UI interfaces.",
        additionalSystemPrompt: SystemPrompt? = nil,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) -> some A2UIAgentStepStream {
        runA2UIAgent(
            messages: [input.toLLMMessage()],
            model: model,
            tools: tools,
            role: role,
            additionalSystemPrompt: additionalSystemPrompt,
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration
        )
    }

    /// 会話履歴を渡すバリアント。
    public func runA2UIAgent(
        messages: [LLMMessage],
        model: Model,
        tools: ToolSet,
        role: String = "You are a helpful assistant that generates A2UI interfaces.",
        additionalSystemPrompt: SystemPrompt? = nil,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) -> some A2UIAgentStepStream {
        let promptBuilder = A2UIPromptBuilder()
        let a2uiPrompt = promptBuilder.buildSystemPrompt(role: role)

        var fullPrompt = SystemPrompt {
            PromptComponent.context(a2uiPrompt)
        }
        if let additional = additionalSystemPrompt {
            fullPrompt = fullPrompt + additional
        }

        return A2UIAgentStepSequence(
            client: self,
            model: model,
            initialMessages: messages,
            tools: tools,
            systemPrompt: fullPrompt,
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration
        )
    }
}
