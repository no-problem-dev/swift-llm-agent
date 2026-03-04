import Foundation
import LLMClient

// MARK: - InteractiveToolConfiguration

/// インタラクティブツールの設定
///
/// LLM のツールセットに注入するインタラクティブツールを定義する。
///
/// - `priorityTools`: LLM のツールセットに注入される少数のインタラクティブツール。
///   エージェント実行中に LLM が呼び出し可能。
/// - `catalog`: 全インタラクティブツールのカタログ。
///
/// ## 使用例
///
/// ```swift
/// let config = InteractiveToolConfiguration(
///     priorityTools: [AskUserTool()],
///     catalog: [AskUserTool(), ConfirmActionTool(), SelectOptionTool()]
/// )
///
/// var turnConfig = TurnConfiguration(
///     systemPrompt: SystemPrompt { "アシスタントです。" },
///     tools: ToolSet { WebSearchTool() },
///     interactiveTools: config
/// )
/// ```
public struct InteractiveToolConfiguration: Sendable {
    /// LLM に注入する優先度の高いインタラクティブツール
    ///
    /// これらのツールは `TurnConfiguration.tools` に自動的に追加され、
    /// LLM が実行中にインタラクションを要求できるようになる。
    public let priorityTools: [any InteractiveTool]

    /// 全インタラクティブツールのカタログ
    public let catalog: [any InteractiveTool]

    public init(
        priorityTools: [any InteractiveTool] = [],
        catalog: [any InteractiveTool] = []
    ) {
        self.priorityTools = priorityTools
        self.catalog = catalog
    }

    // MARK: - Default Guidance

    /// インタラクティブツール使用ガイダンス
    ///
    /// `ask_user` / `ask_selection` / `ask_confirmation` が利用可能な場合に、
    /// LLM が適切にユーザーとインタラクトするための行動指示。
    public static let defaultGuidance = PromptComponent.behavior(
        "ユーザーへの質問や選択肢提示にはインタラクションツールを使う。テキストで質問を書かない。\n\n" +
        "使い分け:\n" +
        "- ask_selection（優先）: 具体的な選択肢を提示できるとき\n" +
        "- ask_user: 自由回答が必要なとき\n" +
        "- ask_confirmation: 実行計画の承認を得たいとき\n\n" +
        "タスクが明確で進行できる場合は、質問せずに進める。"
    )
}
