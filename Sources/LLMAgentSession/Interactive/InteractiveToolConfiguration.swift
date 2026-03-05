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
///     priorityTools: [RequestUserInputTool()]
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
    /// `request_user_input` が利用可能な場合に、
    /// LLM が適切にユーザーとインタラクトするための行動指示。
    public static let defaultGuidance = PromptComponent.behavior(
        "ユーザーに質問や入力を求めるときは request_user_input ツールを使う。" +
        "テキストで質問を直接書かない。\n" +
        "type ヒントを適切に指定すると、最適な UI が自動選択される。\n" +
        "タスクが明確で進行できる場合は、質問せずに進める。"
    )
}
