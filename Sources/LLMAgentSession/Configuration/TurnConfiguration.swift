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
public struct TurnConfiguration: Sendable {

    /// このターンで使用するシステムプロンプト
    public var systemPrompt: SystemPrompt?

    /// このターンで使用可能なツール
    public var tools: ToolSet

    /// このターンのエージェントループ設定
    public var agentConfiguration: AgentConfiguration

    /// ツール実行ポリシー
    ///
    /// 設定されている場合、各ツール呼び出しの実行前にポリシーが評価されます。
    public var executionPolicy: (any ToolExecutionPolicy)?

    public init(
        systemPrompt: SystemPrompt? = nil,
        tools: ToolSet = ToolSet {},
        agentConfiguration: AgentConfiguration = .default,
        executionPolicy: (any ToolExecutionPolicy)? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.agentConfiguration = agentConfiguration
        self.executionPolicy = executionPolicy
    }
}
