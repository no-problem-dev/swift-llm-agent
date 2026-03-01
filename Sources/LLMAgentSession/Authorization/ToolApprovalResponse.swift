import Foundation

// MARK: - ToolApprovalResponse

/// ツール実行承認の応答
///
/// ユーザーが `ToolApprovalRequest` に対して返す応答です。
public enum ToolApprovalResponse: Sendable {
    /// 今回のみ許可
    case allow

    /// セッション中は同じツールを自動許可
    case allowForSession

    /// 拒否
    case deny
}
