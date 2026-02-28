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
///     interactiveMode: true
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

    /// 対話モードを有効にするか
    ///
    /// `true` の場合、`ask_user` ツールが自動的に追加され、
    /// AI がユーザーに質問できるようになります。
    public var interactiveMode: Bool

    public init(
        systemPrompt: SystemPrompt? = nil,
        tools: ToolSet = ToolSet {},
        agentConfiguration: AgentConfiguration = .default,
        interactiveMode: Bool = false
    ) {
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.agentConfiguration = agentConfiguration
        self.interactiveMode = interactiveMode
    }
}
