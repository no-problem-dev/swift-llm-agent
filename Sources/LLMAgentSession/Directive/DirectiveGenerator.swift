import Foundation

// MARK: - DirectiveGenerator

/// ディレクティブ生成プロトコル
///
/// セッション完了後に `StructuredResult` から次のインタラクション提案を生成する。
/// Layer 2 のコンポーネントとして、エージェントの出力型に応じた
/// 適切なインタラクション（アクション、クイックリプライ等）を提案する。
///
/// ## 実装パターン
///
/// ### ルールベース（初期実装）
///
/// ```swift
/// struct RuleBasedDirectiveGenerator: DirectiveGenerator {
///     func generate(from result: StructuredResult) async throws -> InteractionRequest? {
///         switch result.typeName {
///         case "AnalysisResult":
///             return InteractionRequest(
///                 type: .actionMenu,
///                 prompt: "分析結果に基づくアクション",
///                 payload: .actionMenu(
///                     actions: [ActionOption(label: "詳細分析", message: "...")],
///                     quickReplies: [QuickReplyOption(label: "リスク確認", message: "...")]
///                 ),
///                 dismissible: true
///             )
///         default:
///             return nil
///         }
///     }
/// }
/// ```
///
/// ### AI 駆動（将来実装）
///
/// 隔離コンテキストで LLM を呼び出し、出力結果に基づいた
/// 動的なインタラクション提案を生成する。
public protocol DirectiveGenerator: Sendable {
    /// StructuredResult から次のインタラクション提案を生成
    ///
    /// - Parameter result: エージェントの構造化出力結果
    /// - Returns: インタラクション要求。提案がない場合は `nil`
    func generate(from result: StructuredResult) async throws -> InteractionRequest?
}
