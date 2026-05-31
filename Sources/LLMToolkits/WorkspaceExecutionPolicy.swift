import Foundation
import StructuredDataCore
import JSONParsing
import LLMTool
import LLMMCP
import LLMAgentSession

// MARK: - WorkspaceExecutionPolicy

/// ワークスペース境界に基づくツール実行ポリシー
///
/// ファイルシステム操作ツールのパスをワークスペース境界と照合し、
/// 境界内なら自動許可、境界外ならユーザー承認を要求します。
///
/// ## ポリシールール
///
/// | ツール種別 | ルール |
/// |-----------|--------|
/// | 読み取り専用ツール | 常に許可 |
/// | 書き込みツール（境界内） | 自動許可 |
/// | 書き込みツール（境界外） | ユーザー承認が必要 |
/// | 非ファイルシステムツール | 常に許可 |
///
/// ## 使用例
///
/// ```swift
/// let workspace = Workspace(
///     workingDirectory: "/path/to/session",
///     rootDirectory: "/path/to/session"
/// )
/// let policy = WorkspaceExecutionPolicy(workspace: workspace)
///
/// let turn = TurnConfiguration(
///     tools: myToolSet,
///     executionPolicy: policy
/// )
/// ```
public struct WorkspaceExecutionPolicy: ToolExecutionPolicy {
    private let workspace: Workspace

    /// 読み取り専用ツール名（常に許可）
    private static let readOnlyToolNames: Set<String> = [
        "read_file",
        "read_multiple_files",
        "list_directory",
        "directory_tree",
        "search_files",
        "grep_files",
        "get_file_info",
    ]

    /// 書き込みツール名（パスチェックが必要）
    private static let writeToolNames: Set<String> = [
        "write_file",
        "edit_file",
        "create_directory",
        "move_file",
    ]

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    public func evaluate(_ call: ToolCall, tools: ToolSet) async -> ToolExecutionDecision {
        // 読み取り専用ツール → 常に許可
        if Self.readOnlyToolNames.contains(call.name) {
            return .allow
        }

        // 書き込みツール → パスチェック
        if Self.writeToolNames.contains(call.name) {
            return evaluateWriteToolCall(call)
        }

        // 非ファイルシステムツール → 常に許可
        return .allow
    }

    // MARK: - Private

    private func evaluateWriteToolCall(_ call: ToolCall) -> ToolExecutionDecision {
        let paths = extractPaths(from: call)

        for path in paths {
            let resolvedPath = resolvePath(path)
            if !isWithinWorkspace(resolvedPath) {
                return .requiresApproval(request: ToolApprovalRequest(
                    toolCall: call,
                    reason: "ワークスペース外へのファイル操作: \(resolvedPath)",
                    workspaceBoundary: workspace.rootDirectory
                ))
            }
        }

        return .allow
    }

    /// ツール呼び出しからパスを抽出
    private func extractPaths(from call: ToolCall) -> [String] {
        guard let args = try? JSONParser().parse(call.arguments).decode(PathArguments.self) else {
            return []
        }
        return [args.path, args.source, args.destination].compactMap { $0 }
    }

    /// パスを絶対パスに解決
    private func resolvePath(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        let absolute = (workspace.workingDirectory as NSString).appendingPathComponent(expanded)
        return URL(fileURLWithPath: absolute).standardizedFileURL.path
    }

    /// パスがワークスペース内かチェック
    private func isWithinWorkspace(_ path: String) -> Bool {
        let rootPath = URL(fileURLWithPath: workspace.rootDirectory).standardizedFileURL.path
        if path.hasPrefix(rootPath) { return true }
        // 追加の許可パスもチェック
        for allowed in workspace.additionalAllowedPaths {
            let allowedPath = URL(fileURLWithPath: allowed).standardizedFileURL.path
            if path.hasPrefix(allowedPath) { return true }
        }
        return false
    }
}

/// ファイル操作系ツールの引数からパスを抽出するための DTO。
/// 文字列キーは ``CodingKeys`` 既定（プロパティ名一致）に封じ込める。
private struct PathArguments: Decodable {
    let path: String?
    let source: String?
    let destination: String?
}
