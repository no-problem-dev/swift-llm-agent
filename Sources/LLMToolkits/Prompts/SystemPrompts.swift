import Foundation
import LLMClient
import LLMAgentSession

// MARK: - SystemPrompts

/// 構成済みシステムプロンプトカタログ
///
/// Anthropic のコンテキストエンジニアリング原則に基づいて設計:
/// - 最小限の高信号トークン
/// - ツール固有の情報はツール description に委ねる
/// - 過剰な強調表現を排除
///
/// ## 使用例
///
/// ```swift
/// let client = AnthropicClient(apiKey: "...")
///
/// for try await step in client.runAgent(
///     input: "Research the latest AI trends",
///     model: .sonnet,
///     tools: tools,
///     systemPrompt: SystemPromptCatalog.researcher
/// ) {
///     // ステップを処理
/// }
/// ```
public enum SystemPromptCatalog {

    // MARK: - コアエージェントプロンプト

    /// 汎用リサーチアシスタント
    public static let researcher = SystemPrompt(
        "Researcher",
        description: "情報収集、分析、統合タスクに最適化されたリサーチアシスタント",
        iconName: "magnifyingglass",
        tags: ["research", "analysis", "web"]
    ) {
        PromptComponent.role("リサーチアシスタント")
        PromptComponent.objective(
            "情報を収集・分析・統合し、根拠ある洞察を提供する。"
        )
        PromptComponent.instruction(
            "複数ソースを照合し、事実と推測を区別する。情報源を明記する。"
        )
    }

    /// データ分析スペシャリスト
    public static let dataAnalyst = SystemPrompt(
        "Data Analyst",
        description: "数値分析、パターン認識、データ解釈に最適化されたアナリスト",
        iconName: "chart.bar",
        tags: ["data", "analysis", "statistics"]
    ) {
        PromptComponent.role("データアナリスト")
        PromptComponent.objective(
            "データからパターンと実用的な洞察を抽出する。"
        )
        PromptComponent.instruction(
            "統計的根拠を示す。相関と因果を区別する。"
        )
    }

    /// コーディングアシスタント
    public static let codingAssistant = SystemPrompt(
        "Coding Assistant",
        description: "コード生成、デバッグ、リファクタリングに最適化されたアシスタント",
        iconName: "chevron.left.forwardslash.chevron.right",
        tags: ["coding", "development", "engineering"]
    ) {
        PromptComponent.role("ソフトウェアエンジニア")
        PromptComponent.objective(
            "コードの品質・保守性・安全性を評価し、改善する。"
        )
        PromptComponent.instruction(
            "既存のコーディング規約に従い、エッジケースを考慮する。"
        )
    }

    /// ライティング・コンテンツ作成アシスタント
    public static let writer = SystemPrompt(
        "Writer",
        description: "文章の作成、編集、推敲に最適化されたライティングアシスタント",
        iconName: "pencil.line",
        tags: ["writing", "content", "editing"]
    ) {
        PromptComponent.role("プロフェッショナルライター")
        PromptComponent.objective(
            "明確で読者に響くコンテンツを作成・推敲する。"
        )
        PromptComponent.instruction(
            "対象読者とトーンを意識し、冗長な表現を排除する。"
        )
    }

    /// タスク計画・プロジェクト管理アシスタント
    public static let planner = SystemPrompt(
        "Planner",
        description: "タスク計画、プロジェクト管理、作業分解に最適化されたアシスタント",
        iconName: "list.bullet.clipboard",
        tags: ["planning", "project", "management"]
    ) {
        PromptComponent.role("プロジェクトプランナー")
        PromptComponent.objective(
            "実行可能なアクションプランを構造化する。"
        )
        PromptComponent.instruction(
            "依存関係とブロッカーを特定し、現実的な見積もりを提供する。"
        )
    }

    // MARK: - All Prompts

    /// 全プロンプトの一覧
    public static let all: [SystemPrompt] = [
        researcher,
        dataAnalyst,
        codingAssistant,
        writer,
        planner,
    ]
}

// MARK: - AgentBehaviors

/// エージェントプロンプト用のコア行動コンポーネント
///
/// GPT-4.1 Prompting Guide の調査結果に基づく。
/// これら3要素により SWE-bench Verified スコアが約20%向上。
public enum AgentBehaviors {

    /// 持続性の行動指示
    ///
    /// タスクが完全に完了するまでエージェントが作業を継続することを保証します。
    /// 出典: GPT-4.1 Prompting Guide
    public static let persistence = PromptComponent.behavior(
        "You are an agent. Keep working until the user's query is completely resolved " +
        "before ending your turn and yielding back to the user. Do not stop at partial " +
        "solutions or incomplete answers."
    )

    /// ツール呼び出しの行動指示
    ///
    /// エージェントが推測ではなくツールを使って情報を収集することを保証します。
    /// 出典: GPT-4.1 Prompting Guide
    public static let toolCalling = PromptComponent.behavior(
        "If you are not certain about information relevant to the user's request, " +
        "use available tools to gather accurate data. Do NOT guess or make assumptions " +
        "when tools can provide verified information."
    )

    /// 計画立案の行動指示
    ///
    /// エージェントが行動前に計画を立て、結果を振り返ることを保証します。
    /// 出典: GPT-4.1 Prompting Guide
    public static let planning = PromptComponent.behavior(
        "Plan extensively before each action or tool call. After receiving results, " +
        "reflect on the outcomes and adjust your approach as needed. Think step by step."
    )

    /// ステップ予算意識の行動指示
    ///
    /// エージェントがステップ予算を意識して効率的にツールを使用することを保証します。
    public static let stepBudgetAwareness = PromptComponent.behavior(
        "You have a limited number of steps to complete this task. Be efficient with tool usage: " +
        "batch related queries, avoid redundant calls, and prefer getting multiple pieces of information " +
        "in a single step when possible. If you receive a warning about remaining steps, immediately " +
        "consolidate your findings and produce your final output."
    )

    /// 自律的行動の指示
    ///
    /// エージェントが不必要にユーザーに質問しないことを保証します。
    /// インタラクションツールが利用可能な場合は、テキスト応答ではなくツール経由で問い合わせることを指示します。
    public static let autonomy = PromptComponent.behavior(
        "Act autonomously and make reasonable decisions on your own. " +
        "Do NOT generate plain-text questions or option lists in your response. " +
        "When you need user input, you MUST use the appropriate interaction tool " +
        "(request_user_input) instead of writing questions or choices as text. " +
        "When the task is clear and you can proceed without user input, " +
        "proceed with your best judgment."
    )

    /// Web リサーチワークフローの指示
    ///
    /// 「検索→URL取得→fetch」の正しいワークフローを指示し、URL推測を禁止します。
    public static let webResearchWorkflow = PromptComponent.behavior(
        "When researching online: ALWAYS use web_search first to find relevant URLs. " +
        "NEVER guess or fabricate URLs — this leads to 404 errors and wastes steps. " +
        "The correct workflow is: (1) web_search to discover URLs, (2) fetch " +
        "to retrieve content from discovered URLs. If a fetch fails, search for alternative sources " +
        "rather than retrying the same URL."
    )

    /// リサーチ品質の指示
    ///
    /// ソース引用、具体例、事実/意見の区別を要求します。
    public static let researchQuality = PromptComponent.behavior(
        "Ensure high-quality research output: cite specific sources with URLs when available, " +
        "include concrete data points and examples, clearly distinguish between verified facts " +
        "and opinions/speculation, and provide a balanced view covering multiple perspectives. " +
        "If information is incomplete, explicitly state what could not be verified."
    )

    /// インタラクティブツール使用ガイダンス
    ///
    /// `request_user_input` が利用可能な場合に、
    /// LLM が適切にユーザーとインタラクトするための行動指示。
    /// `InteractiveToolConfiguration.defaultGuidance` を参照。
    public static let interactiveGuidance = InteractiveToolConfiguration.defaultGuidance

    /// 統合エージェント行動指示
    ///
    /// 便利のために3つのコア行動指示をすべて含みます。
    public static let allBehaviors = SystemPrompt {
        persistence
        toolCalling
        planning
        stepBudgetAwareness
    }
}

// MARK: - PromptModifiers

/// 任意のシステムプロンプトに適用可能な修飾子
public enum PromptModifiers {

    /// 出力フォーマット指定を追加
    ///
    /// - Parameter format: 期待する出力フォーマットの説明
    /// - Returns: 出力フォーマットを指定するプロンプトコンポーネント
    public static func outputFormat(_ format: String) -> PromptComponent {
        .instruction("Format your response as: \(format)")
    }

    /// 言語指定を追加
    ///
    /// - Parameter language: 応答の言語（例: "English", "Japanese"）
    /// - Returns: 応答言語を指定するプロンプトコンポーネント
    public static func responseLanguage(_ language: String) -> PromptComponent {
        .instruction("Respond in \(language).")
    }

    /// 詳細度の制御
    public enum Verbosity {
        case concise
        case detailed
        case comprehensive

        var instruction: PromptComponent {
            switch self {
            case .concise:
                return .instruction(
                    "Keep responses concise and to the point. " +
                    "Avoid unnecessary elaboration."
                )
            case .detailed:
                return .instruction(
                    "Provide detailed explanations with supporting context. " +
                    "Include relevant background information."
                )
            case .comprehensive:
                return .instruction(
                    "Provide comprehensive coverage of the topic. " +
                    "Include all relevant details, edge cases, and considerations."
                )
            }
        }
    }

    /// 専門レベルのターゲティング
    public enum ExpertiseLevel {
        case beginner
        case intermediate
        case expert

        var instruction: PromptComponent {
            switch self {
            case .beginner:
                return .instruction(
                    "Explain concepts in simple terms, avoiding jargon. " +
                    "Provide context and definitions for technical terms."
                )
            case .intermediate:
                return .instruction(
                    "Assume familiarity with basic concepts. " +
                    "Focus on practical application and nuanced understanding."
                )
            case .expert:
                return .instruction(
                    "Use precise technical terminology. " +
                    "Focus on advanced concepts and edge cases."
                )
            }
        }
    }
}

// MARK: - SystemPrompt Extension

extension SystemPrompt {

    /// ベースプロンプトと修飾子を組み合わせてカスタマイズされたプロンプトを作成
    ///
    /// - Parameters:
    ///   - base: ベースとなるシステムプロンプト
    ///   - modifiers: 追加するプロンプトコンポーネント
    /// - Returns: ベースと修飾子を組み合わせた新しいプロンプト
    ///
    /// ## 使用例
    ///
    /// ```swift
    /// let customPrompt = SystemPrompt.customized(
    ///     base: SystemPromptCatalog.researcher,
    ///     modifiers: [
    ///         PromptModifiers.responseLanguage("Japanese"),
    ///         PromptModifiers.Verbosity.concise.instruction
    ///     ]
    /// )
    /// ```
    public static func customized(
        base: SystemPrompt,
        modifiers: [PromptComponent]
    ) -> SystemPrompt {
        SystemPrompt(components: base.components + modifiers)
    }
}
