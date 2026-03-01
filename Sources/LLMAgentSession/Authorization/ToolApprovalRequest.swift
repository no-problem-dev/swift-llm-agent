import Foundation
import LLMTool

// MARK: - ToolApprovalRequest

/// ツール実行の承認リクエスト
///
/// ポリシーがユーザー承認を必要と判断した場合に生成されます。
/// UI 層がこのリクエストを表示し、ユーザーの応答を
/// `ToolApprovalResponse` として返します。
public struct ToolApprovalRequest: Sendable, Identifiable, Equatable {
    /// リクエスト ID
    public let id: UUID

    /// 承認対象のツール呼び出し
    public let toolCall: ToolCall

    /// 承認が必要な理由（UI に表示される）
    public let reason: String

    /// ツールのアノテーション情報（UI のヒント用）
    public let toolAnnotations: ToolAnnotations?

    /// ワークスペース境界パス（UI で境界表示に使用）
    public let workspaceBoundary: String?

    public init(
        id: UUID = UUID(),
        toolCall: ToolCall,
        reason: String,
        toolAnnotations: ToolAnnotations? = nil,
        workspaceBoundary: String? = nil
    ) {
        self.id = id
        self.toolCall = toolCall
        self.reason = reason
        self.toolAnnotations = toolAnnotations
        self.workspaceBoundary = workspaceBoundary
    }
}
