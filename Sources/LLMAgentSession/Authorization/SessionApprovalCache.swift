import Foundation

// MARK: - SessionApprovalCache

/// セッション内のツール承認キャッシュ
///
/// `ToolApprovalResponse.allowForSession` で承認されたツール名を記録し、
/// 同一セッション内での再承認をスキップします。
public actor SessionApprovalCache {
    /// 承認済みツール名
    private var approvedToolNames: Set<String> = []

    public init() {}

    /// ツールが承認済みかチェック
    ///
    /// - Parameter toolName: チェックするツール名
    /// - Returns: セッション内で承認済みの場合 `true`
    public func isApproved(_ toolName: String) -> Bool {
        approvedToolNames.contains(toolName)
    }

    /// ツールをセッション承認済みとして記録
    ///
    /// - Parameter toolName: 承認するツール名
    public func approve(_ toolName: String) {
        approvedToolNames.insert(toolName)
    }

    /// キャッシュをクリア
    public func clear() {
        approvedToolNames.removeAll()
    }
}
