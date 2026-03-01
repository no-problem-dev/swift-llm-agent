import Foundation
import LLMTool

/// パーミッションチェックを ToolResult に統合するユーティリティ
///
/// ToolKit の各ツール実行前にパーミッションを確認し、
/// 未認可の場合はユーザーにわかりやすいエラーを返します。
///
/// ## 使用例（ToolKit 内部）
///
/// ```swift
/// let guard = PermissionGuard(provider: eventPermission)
///
/// BuiltInTool(name: "search_events", ...) { data in
///     if let error = await guard.ensureAuthorized() {
///         return error  // ToolResult.error(...)
///     }
///     // ... 通常の処理
/// }
/// ```
public struct PermissionGuard: Sendable {
    private let provider: any PermissionProvider

    public init(provider: any PermissionProvider) {
        self.provider = provider
    }

    /// 認可済みかチェックし、未決定なら認可を要求する
    ///
    /// - Returns: `nil`（認可済み）または `ToolResult.error`（拒否・制限）
    public func ensureAuthorized() async -> ToolResult? {
        switch await provider.resolvedStatus() {
        case .authorized:
            return nil
        case .notDetermined:
            do {
                let status = try await provider.requestAuthorization()
                if status == .authorized { return nil }
                return deniedResult()
            } catch {
                return .error(
                    "Failed to request \(provider.permissionName) permission: "
                    + "\(error.localizedDescription)"
                )
            }
        case .denied:
            return deniedResult()
        case .restricted:
            return .error(
                "Access to \(provider.permissionName) is restricted on this device. "
                + "This may be due to parental controls or device management."
            )
        }
    }

    private func deniedResult() -> ToolResult {
        .error(
            "Permission denied for \(provider.permissionName). "
            + "Please enable access in Settings > Privacy & Security > "
            + "\(provider.settingsPath)."
        )
    }
}
