import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - TurnConfiguration

/// ターンごとの設定
///
/// エージェントセッションの各ターン（`run()` / `resume()` 呼び出し）で
/// 使用される設定をバンドルします。
///
/// セッション自体は会話履歴のみを保持し、ツール・システムプロンプト・
/// エージェント設定はターンごとに変更可能です。
///
/// ## 使用例
///
/// ```swift
/// // 初回のターン設定
/// var config = TurnConfiguration(
///     systemPrompt: SystemPrompt { "リサーチアシスタントです。" },
///     tools: ToolSet { WebSearchTool() },
///     agentConfiguration: .default,
///     interactiveTools: InteractiveToolConfiguration(
///         priorityTools: [RequestUserInputTool()]
///     )
/// )
///
/// // ターン間でツールを追加
/// config.tools = config.tools.appending(NewTool())
///
/// // ターン間でシステムプロンプトを変更
/// config.systemPrompt = SystemPrompt { "コードレビューアです。" }
/// ```
public struct TurnConfiguration: Sendable {

    /// このターンで使用するシステムプロンプト
    ///
    /// `nil` の場合、システムプロンプトなしで LLM を呼び出します。
    public var systemPrompt: SystemPrompt?

    /// このターンで使用可能なツール
    public var tools: ToolSet

    /// このターンのエージェントループ設定
    ///
    /// `maxSteps`, `thinkingMode`, `skipFinalOutput` などを含みます。
    public var agentConfiguration: AgentConfiguration

    /// インタラクティブツール設定
    ///
    /// 設定されている場合、`priorityTools` が自動的にツールセットに追加され、
    /// AI がユーザーにインタラクションを要求できるようになります。
    /// `nil` の場合、インタラクティブモードは無効です。
    public var interactiveTools: InteractiveToolConfiguration?

    /// ツール実行ポリシー
    ///
    /// 設定されている場合、各ツール呼び出しの実行前にポリシーが評価されます。
    /// ポリシーがユーザー承認を要求した場合、ランループは suspend し、
    /// UI が `respondToAuthorization()` を呼ぶまで待機します。
    /// `nil` の場合、全ツール呼び出しが無条件で実行されます。
    public var executionPolicy: (any ToolExecutionPolicy)?

    public init(
        systemPrompt: SystemPrompt? = nil,
        tools: ToolSet = ToolSet {},
        agentConfiguration: AgentConfiguration = .default,
        interactiveTools: InteractiveToolConfiguration? = nil,
        executionPolicy: (any ToolExecutionPolicy)? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.agentConfiguration = agentConfiguration
        self.interactiveTools = interactiveTools
        self.executionPolicy = executionPolicy
    }
}
