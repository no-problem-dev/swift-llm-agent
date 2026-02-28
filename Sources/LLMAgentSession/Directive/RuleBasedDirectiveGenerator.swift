import Foundation

// MARK: - RuleBasedDirectiveGenerator

/// ルールベースのディレクティブ生成器
///
/// `StructuredResult.typeName` に基づいて、適切なインタラクション提案を生成する。
/// AI 駆動の DirectiveGenerator が実装されるまでの初期実装。
///
/// ## サポートする typeName
///
/// | typeName | 生成されるインタラクション |
/// |----------|------------------------|
/// | AnalysisResult | 推奨事項実行、詳細分析、リスク対策等 |
/// | CodeReview | 修正コード生成、改善適用、テスト追加等 |
/// | TaskPlan | 計画実行、修正、却下、リスク対策等 |
/// | Summary | 詳細表示、関連トピック、実用例等 |
/// | その他 | 詳細表示、要約のクイックリプライ |
/// | PlainText | nil（ディレクティブなし） |
///
/// ## 使用例
///
/// ```swift
/// let generator = RuleBasedDirectiveGenerator()
/// let session = InteractiveAgentSession(
///     chatSession: chatSession,
///     directiveGenerator: generator
/// )
/// ```
public struct RuleBasedDirectiveGenerator: DirectiveGenerator, Sendable {
    public init() {}

    public func generate(from result: StructuredResult) async throws -> InteractionRequest? {
        switch result.typeName {
        case "AnalysisResult":
            return analysisDirective(result)
        case "CodeReview":
            return reviewDirective(result)
        case "TaskPlan":
            return planDirective(result)
        case "Summary":
            return summaryDirective(result)
        case "PlainText":
            return nil
        default:
            return markdownDirective()
        }
    }

    // MARK: - Analysis

    private func analysisDirective(_ result: StructuredResult) -> InteractionRequest {
        let sectionTitles = Set(result.sections.map(\.title))
        var actions: [ActionOption] = []

        if sectionTitles.contains("推奨事項") {
            actions.append(ActionOption(
                id: "analysis-execute",
                label: "推奨事項を実行",
                icon: "play.fill",
                style: .primary,
                message: "推奨事項を実行してください"
            ))
        }

        actions.append(ActionOption(
            id: "analysis-detail",
            label: "詳細分析",
            icon: "magnifyingglass",
            style: .standard,
            message: "この分析結果をさらに詳しく分析してください"
        ))

        let quickReplies = [
            QuickReplyOption(id: "analysis-qr1", label: "リスク対策", icon: "shield", message: "リスクへの対策を提案してください"),
            QuickReplyOption(id: "analysis-qr2", label: "データの根拠", icon: "chart.bar", message: "分析の根拠となるデータを詳しく教えてください"),
            QuickReplyOption(id: "analysis-qr3", label: "別の観点で", icon: "arrow.triangle.branch", message: "別の観点から分析してください"),
        ]

        return InteractionRequest(
            type: .actionMenu,
            prompt: "分析結果に基づくアクション",
            payload: .actionMenu(actions: actions, quickReplies: quickReplies),
            dismissible: true
        )
    }

    // MARK: - Review

    private func reviewDirective(_ result: StructuredResult) -> InteractionRequest {
        let sectionTitles = Set(result.sections.map(\.title))
        var actions: [ActionOption] = []

        if sectionTitles.contains("問題点") {
            actions.append(ActionOption(
                id: "review-fix",
                label: "修正コード生成",
                icon: "hammer",
                style: .primary,
                message: "指摘された問題点の修正コードを生成してください"
            ))
        }

        if sectionTitles.contains("改善提案") {
            actions.append(ActionOption(
                id: "review-improve",
                label: "改善を適用",
                icon: "sparkles",
                style: .standard,
                message: "改善提案を適用したコードを生成してください"
            ))
        }

        let quickReplies = [
            QuickReplyOption(id: "review-qr1", label: "テスト追加", icon: "testtube.2", message: "この部分のテストコードを生成してください"),
            QuickReplyOption(id: "review-qr2", label: "パフォーマンス", icon: "gauge.with.dots.needle.67percent", message: "パフォーマンスの観点でレビューしてください"),
            QuickReplyOption(id: "review-qr3", label: "セキュリティ", icon: "lock.shield", message: "セキュリティの観点でレビューしてください"),
        ]

        return InteractionRequest(
            type: .actionMenu,
            prompt: "コードレビュー結果に基づくアクション",
            payload: .actionMenu(actions: actions, quickReplies: quickReplies),
            dismissible: true
        )
    }

    // MARK: - Plan

    private func planDirective(_ result: StructuredResult) -> InteractionRequest {
        let actions = [
            ActionOption(
                id: "plan-execute",
                label: "計画を実行",
                icon: "play.fill",
                style: .primary,
                message: "この計画を実行してください"
            ),
            ActionOption(
                id: "plan-modify",
                label: "修正",
                icon: "pencil",
                style: .standard,
                message: "この計画を修正してください"
            ),
            ActionOption(
                id: "plan-reject",
                label: "却下",
                icon: "xmark",
                style: .destructive,
                message: "この計画を却下します。別のアプローチを提案してください"
            ),
        ]

        let quickReplies = [
            QuickReplyOption(id: "plan-qr1", label: "リスク対策を追加", icon: "shield", message: "計画にリスク対策を追加してください"),
            QuickReplyOption(id: "plan-qr2", label: "工数見積もり", icon: "clock", message: "各ステップの工数を見積もってください"),
            QuickReplyOption(id: "plan-qr3", label: "前提確認", icon: "checkmark.circle", message: "計画の前提条件を確認してください"),
        ]

        return InteractionRequest(
            type: .actionMenu,
            prompt: "タスク計画に基づくアクション",
            payload: .actionMenu(actions: actions, quickReplies: quickReplies),
            dismissible: true
        )
    }

    // MARK: - Summary

    private func summaryDirective(_ result: StructuredResult) -> InteractionRequest {
        let actions = [
            ActionOption(
                id: "summary-detail",
                label: "さらに詳しく",
                icon: "magnifyingglass",
                style: .primary,
                message: "この内容をさらに詳しく教えてください"
            ),
        ]

        let quickReplies = [
            QuickReplyOption(id: "summary-qr1", label: "関連トピック", icon: "link", message: "関連するトピックを教えてください"),
            QuickReplyOption(id: "summary-qr2", label: "実用的な例", icon: "lightbulb", message: "実用的な例を挙げてください"),
            QuickReplyOption(id: "summary-qr3", label: "箇条書き", icon: "list.bullet", message: "要点を箇条書きで整理してください"),
            QuickReplyOption(id: "summary-qr4", label: "図解", icon: "chart.pie", message: "図解で説明してください"),
        ]

        return InteractionRequest(
            type: .actionMenu,
            prompt: "サマリーに基づくアクション",
            payload: .actionMenu(actions: actions, quickReplies: quickReplies),
            dismissible: true
        )
    }

    // MARK: - Markdown Fallback

    private func markdownDirective() -> InteractionRequest {
        let quickReplies = [
            QuickReplyOption(id: "md-qr1", label: "さらに詳しく", icon: "magnifyingglass", message: "この内容をさらに詳しく教えてください"),
            QuickReplyOption(id: "md-qr2", label: "要約", icon: "doc.text", message: "要点をまとめてください"),
        ]

        return InteractionRequest(
            type: .actionMenu,
            prompt: "次のアクション",
            payload: .actionMenu(actions: [], quickReplies: quickReplies),
            dismissible: true
        )
    }
}
