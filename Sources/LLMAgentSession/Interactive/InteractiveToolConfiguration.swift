import Foundation
import LLMClient

// MARK: - InteractiveToolConfiguration

/// インタラクティブツールの設定
///
/// Layer 1（実行中インタラクション）と Layer 2（完了後ディレクティブ）で
/// 使用するインタラクティブツールを定義する。
///
/// ## 2 層構成
///
/// - `priorityTools`: LLM のツールセットに注入される少数のインタラクティブツール。
///   エージェント実行中に LLM が呼び出し可能。
/// - `catalog`: 全インタラクティブツールのカタログ。
///   Layer 2 の DirectiveGenerator が利用可能な UX パターンとして参照する。
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
    ///
    /// Layer 2 の DirectiveGenerator が、利用可能な UX パターンとして参照する。
    /// priorityTools も含めて定義することを推奨。
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
        "CRITICAL RULE: You MUST NEVER write questions, option lists, or confirmation requests " +
        "as plain text in your response. When you need user input, you MUST call the appropriate " +
        "interaction tool. Outputting questions or choices as text is a failure mode.\n\n" +
        "Tool selection rules:\n" +
        "1. ask_selection (PREFERRED): When you can identify 2-10 specific options. " +
        "Examples: suggesting research topics, choosing between approaches, " +
        "selecting a format or style. ALWAYS prefer this over ask_user.\n" +
        "2. ask_user: ONLY when the answer is truly open-ended and cannot be anticipated " +
        "(e.g., 'What is your name?', 'Describe your use case').\n" +
        "3. ask_confirmation: When you have a specific plan and want approval before executing.\n\n" +
        "You MUST use these tools when:\n" +
        "- The request is vague (e.g., '調べて', '何か教えて', 'help me with something').\n" +
        "- The user explicitly asks for options, suggestions, or choices.\n" +
        "- Multiple valid approaches exist and the choice affects the outcome.\n\n" +
        "You should proceed WITHOUT asking when:\n" +
        "- The task is clear and specific enough to execute directly.\n" +
        "- You can gather the needed information through other tools (web_search, etc.)."
    )
}
