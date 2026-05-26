import Foundation
import LLMClient
import LLMTool

// MARK: - AgentCapableClient + Text Agent

extension AgentCapableClient {
    /// 構造化出力を要求しないエージェントループを実行する。
    ///
    /// `runAgent<Output: StructuredProtocol>` と異なり、最終出力フェーズで
    /// 構造化 JSON の生成を強制しない。LLM の応答にツール呼び出しが含まれなくなった
    /// 段階で、その応答テキストを `.finalText(String)` として発行して終了する。
    ///
    /// A2UI のように「テキスト応答中の JSON コードブロックを後段でパースする」、
    /// あるいは純粋なチャット応答用途に適している。
    ///
    /// ## 使用例
    ///
    /// ```swift
    /// let stream = client.runAgentText(
    ///     input: "次の予定をまとめて",
    ///     model: .gpt5Mini,
    ///     tools: tools
    /// )
    /// for try await step in stream {
    ///     switch step {
    ///     case .thinking, .toolCall, .toolResult:
    ///         break
    ///     case .finalText(let text):
    ///         // 後段でテキストを自由に処理
    ///         break
    ///     }
    /// }
    /// ```
    public func runAgentText(
        input: LLMInput,
        model: Model,
        tools: ToolSet,
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default
    ) -> some AgentTextStepStream {
        runAgentText(
            messages: [input.toLLMMessage()],
            model: model,
            tools: tools,
            systemPrompt: systemPrompt,
            configuration: configuration
        )
    }

    /// 会話履歴を渡すバリアント。
    public func runAgentText(
        messages: [LLMMessage],
        model: Model,
        tools: ToolSet,
        systemPrompt: SystemPrompt? = nil,
        configuration: AgentConfiguration = .default
    ) -> some AgentTextStepStream {
        let context = AgentContext(
            systemPrompt: systemPrompt,
            tools: tools,
            initialMessages: messages,
            configuration: configuration
        )

        return TextAgentStepSequence<Self>(
            client: self,
            model: model,
            context: context,
            configuration: configuration
        )
    }
}
