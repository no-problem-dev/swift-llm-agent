import Foundation
import LLMTool

// MARK: - ToolExecutionDecision

/// ツール実行ポリシーの評価結果
///
/// ポリシーがツール呼び出しを評価した結果を表します。
///
/// - `.allow`: 即座に実行を許可
/// - `.deny(reason:)`: 実行を拒否（エラーレスポンスとして LLM に返される）
/// - `.requiresApproval(request:)`: ユーザー承認が必要
public enum ToolExecutionDecision: Sendable {
    /// 実行を許可
    case allow

    /// 実行を拒否
    ///
    /// - Parameter reason: 拒否理由（ToolResponse のエラーメッセージに使用される）
    case deny(reason: String)

    /// ユーザー承認が必要
    ///
    /// - Parameter request: 承認リクエスト（UI に表示される）
    case requiresApproval(request: ToolApprovalRequest)
}

// MARK: - ToolExecutionPolicy

/// ツール実行ポリシー
///
/// エージェントループ内でツール呼び出しを実行する前に評価されるポリシーです。
/// ワークスペース境界チェック、権限管理、安全性ゲートなど、
/// 任意のポリシーロジックを実装できます。
///
/// ## 使用例
///
/// ```swift
/// struct MyPolicy: ToolExecutionPolicy {
///     func evaluate(_ call: ToolCall, tools: ToolSet) async -> ToolExecutionDecision {
///         if call.name == "dangerous_tool" {
///             return .requiresApproval(request: ToolApprovalRequest(
///                 toolCall: call,
///                 reason: "This tool performs a destructive operation."
///             ))
///         }
///         return .allow
///     }
/// }
/// ```
public protocol ToolExecutionPolicy: Sendable {
    /// ツール呼び出しを評価
    ///
    /// - Parameters:
    ///   - call: 評価対象のツール呼び出し
    ///   - tools: 現在のツールセット（ツールのアノテーション等の取得に使用）
    /// - Returns: 実行許可・拒否・承認要求のいずれか
    func evaluate(_ call: ToolCall, tools: ToolSet) async -> ToolExecutionDecision
}
