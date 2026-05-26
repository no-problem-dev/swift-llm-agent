import Foundation
import LLMClient
import LLMTool

// Re-export for downstream consumers
public typealias ThinkingMode = LLMClient.ThinkingMode

// MARK: - AgentLoopStep

/// エージェントループの各ステップを表す
///
/// AsyncSequence で返される各要素として使用されます。
///
/// - Note: `LLMAgentSession.AgentStep` とは異なる型です。
///   こちらはループ内部の実行ステップ（ジェネリクス付き）、
///   `AgentStep` はセッション表示用のイベント（非ジェネリクス）です。
///
/// ## 使用例
///
/// ```swift
/// for try await step in client.runAgent(input: "天気を調べて", tools: tools) {
///     switch step {
///     case .thinking(let response):
///         print("思考中: \(response.textContent ?? "")")
///     case .toolCall(let call):
///         print("ツール呼び出し: \(call.name)")
///     case .toolResult(let result):
///         print("ツール結果: \(result.output)")
///     case .finalResponse(let output):
///         print("最終結果: \(output)")
///     }
/// }
/// ```
public enum AgentLoopStep<Output: Sendable>: Sendable {
    /// LLM が思考中（テキスト応答を生成）
    case thinking(LLMResponse)

    /// LLM がツール呼び出しを要求
    case toolCall(ToolCall)

    /// ツール実行結果
    case toolResult(ToolResponse)

    /// エージェントループ完了、最終出力
    case finalResponse(Output)
}

// MARK: - AgentConfiguration

/// エージェントループの設定
public struct AgentConfiguration: Sendable {
    /// 最大ステップ数（無限ループ防止）
    public let maxSteps: Int

    /// ソフトリミットステップ数
    ///
    /// このステップに到達すると「残りステップが少ない」旨のメッセージを
    /// 会話履歴に注入し、エージェントにまとめを促します。
    /// デフォルトは `max(1, maxSteps - 2)`。
    public let softMaxSteps: Int

    /// ツール実行を自動で行うか
    public let autoExecuteTools: Bool

    /// 重複ツール呼び出しの最大許容回数（同一ツール・同一入力）
    ///
    /// LLM が同じツールを同じ引数で繰り返し呼び出す場合、
    /// この回数を超えるとループを終了します。
    public let maxDuplicateToolCalls: Int

    /// 同一ツールの最大総呼び出し回数
    ///
    /// 同じツールが（異なる引数でも）この回数を超えて呼ばれた場合、
    /// ループを終了します。これにより、同じツールを延々と
    /// 異なるクエリで呼び続けるパターンを防止します。
    ///
    /// - Note: `nil` の場合は制限なし（maxSteps でのみ制限）
    public let maxToolCallsPerTool: Int?

    /// インタラクティブツールの最大呼び出し回数
    ///
    /// エージェントが InteractiveTool でユーザーにインタラクションを要求する回数を制限します。
    /// - `nil`: 無制限（デフォルト）
    /// - `0`: インタラクションを禁止（自律的に判断）
    /// - 正の値: 指定回数まで許可
    public let maxInteractiveCalls: Int?

    /// 複数ツールコールの並列実行を許可するか
    ///
    /// `true` の場合、LLM が1回のレスポンスで複数のツールコールを返した際に
    /// `TaskGroup` で並列実行します（デフォルト）。
    ///
    /// `false` の場合、ツールコールを LLM の出力順に逐次実行します。
    /// `emit_block` のように実行順序が表示順序に直結するツールでは
    /// `false` に設定してください。
    public let parallelToolExecution: Bool

    /// Extended Thinking のモード
    ///
    /// `.adaptive` に設定すると、Claude の Extended Thinking を有効にし、
    /// 思考プロセスをストリーミングで返します。
    public let thinkingMode: ThinkingMode

    /// OpenAI reasoning モデル (GPT-5 系) の `reasoning_effort` 設定
    ///
    /// `nil` の場合は API のデフォルト（一般に `medium`）が使われる。
    /// `.low` を指定するとレイテンシ／コストを大幅に下げられる。
    /// `.minimal` は parallel tool call が無効化される点に注意。
    /// Anthropic / Gemini など、非対応プロバイダーでは無視される。
    public let reasoningEffort: ReasoningEffort?

    /// 構造化出力フェーズをスキップするか
    ///
    /// `true` の場合、ツール呼び出しが完了した後に finalOutput フェーズ
    /// （構造化 JSON 出力要求）をスキップし、LLM のテキスト応答をそのまま返します。
    ///
    /// ローカル LLM など、構造化 JSON 出力が安定しないモデルに適しています。
    public let skipFinalOutput: Bool

    /// 各 LLM コールの最大出力トークン数
    ///
    /// `nil` の場合、プラットフォーム/モデルのデフォルトが使用される。
    /// 調査タスクや長い出力が期待される場合は大きめに設定する（例: 16384）。
    public let maxTokens: Int?

    /// デフォルト設定
    public static let `default` = AgentConfiguration(
        maxSteps: 10,
        autoExecuteTools: true,
        maxDuplicateToolCalls: 1,
        maxToolCallsPerTool: 5
    )

    public init(
        maxSteps: Int = 10,
        softMaxSteps: Int? = nil,
        autoExecuteTools: Bool = true,
        maxDuplicateToolCalls: Int = 1,
        maxToolCallsPerTool: Int? = 5,
        maxInteractiveCalls: Int? = nil,
        parallelToolExecution: Bool = true,
        thinkingMode: ThinkingMode = .disabled,
        reasoningEffort: ReasoningEffort? = nil,
        skipFinalOutput: Bool = false,
        maxTokens: Int? = nil
    ) {
        self.maxSteps = maxSteps
        self.softMaxSteps = softMaxSteps ?? max(1, maxSteps - 2)
        self.autoExecuteTools = autoExecuteTools
        self.maxDuplicateToolCalls = maxDuplicateToolCalls
        self.maxToolCallsPerTool = maxToolCallsPerTool
        self.maxInteractiveCalls = maxInteractiveCalls
        self.parallelToolExecution = parallelToolExecution
        self.thinkingMode = thinkingMode
        self.reasoningEffort = reasoningEffort
        self.skipFinalOutput = skipFinalOutput
        self.maxTokens = maxTokens
    }

    /// バックグラウンド実行用の設定を返す
    ///
    /// インタラクティブツールを禁止した設定のコピーを返します。
    /// バックグラウンドではユーザーとのインタラクションが不可能なため、
    /// `maxInteractiveCalls` を `0` に設定します。
    public var forBackground: AgentConfiguration {
        AgentConfiguration(
            maxSteps: maxSteps,
            softMaxSteps: softMaxSteps,
            autoExecuteTools: autoExecuteTools,
            maxDuplicateToolCalls: maxDuplicateToolCalls,
            maxToolCallsPerTool: maxToolCallsPerTool,
            maxInteractiveCalls: 0,
            parallelToolExecution: parallelToolExecution,
            thinkingMode: thinkingMode,
            reasoningEffort: reasoningEffort,
            skipFinalOutput: skipFinalOutput,
            maxTokens: maxTokens
        )
    }
}

// MARK: - AgentError

/// エージェントループ固有のエラー
public enum AgentError: Error, Sendable {
    /// 最大ステップ数を超過
    case maxStepsExceeded(steps: Int)

    /// ツールが見つからない
    case toolNotFound(name: String)

    /// ツール実行エラー
    case toolExecutionFailed(name: String, underlyingError: Error)

    /// 無効な状態
    case invalidState(String)

    /// 出力のデコードに失敗
    case outputDecodingFailed(Error)

    /// LLMエラーをラップ
    case llmError(LLMError)

    /// 終了ポリシーによりループが中断された
    ///
    /// 重複ツール呼び出し検出やツール呼び出し回数上限到達など、
    /// 終了ポリシーがループの即時終了を決定した場合に発生します。
    case terminatedByPolicy(String)
}

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .maxStepsExceeded(let steps):
            return "Agent exceeded maximum steps limit (\(steps))"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .toolExecutionFailed(let name, let error):
            return "Tool execution failed (\(name)): \(error.localizedDescription)"
        case .invalidState(let message):
            return "Invalid agent state: \(message)"
        case .outputDecodingFailed(let error):
            return "Failed to decode output: \(error.localizedDescription)"
        case .llmError(let error):
            return "LLM error: \(error.localizedDescription)"
        case .terminatedByPolicy(let reason):
            return "Agent loop terminated by policy: \(reason)"
        }
    }
}

// MARK: - StopReason Extension

extension LLMResponse.StopReason {
    /// ツール呼び出しによる停止かどうか
    public var isToolUse: Bool {
        self == .toolUse
    }
}
