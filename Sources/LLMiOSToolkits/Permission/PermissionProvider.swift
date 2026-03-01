import Foundation

/// iOS フレームワークのパーミッションを抽象化するプロトコル
///
/// 各 iOS ToolKit がパーミッション管理を統一的に扱えるようにします。
/// EventKit、CoreLocation、HealthKit など各フレームワーク固有の
/// 認可 API を共通インターフェースでラップします。
///
/// ## 実装例
///
/// ```swift
/// struct CalendarEventPermission: PermissionProvider {
///     let eventStore: EKEventStore
///     var permissionName: String { "Calendar Events" }
///     var settingsPath: String { "Calendars" }
///
///     func currentStatus() -> PermissionStatus { ... }
///     func requestAuthorization() async throws -> PermissionStatus { ... }
/// }
/// ```
public protocol PermissionProvider: Sendable {
    /// パーミッションの表示名（エラーメッセージで使用）
    var permissionName: String { get }

    /// Settings.app で表示されるプライバシー設定のパス案内
    var settingsPath: String { get }

    /// 現在の認可状態を同期的に確認
    func currentStatus() -> PermissionStatus

    /// 現在の認可状態を可能な限り正確に確認
    ///
    /// 非同期 API が必要なフレームワーク（例: 通知）向け。
    /// デフォルトでは ``currentStatus()`` をそのまま返します。
    func resolvedStatus() async -> PermissionStatus

    /// 認可をリクエスト
    ///
    /// `.notDetermined` の場合にシステムダイアログを表示します。
    /// すでに判断済みの場合は現在の状態をそのまま返します。
    func requestAuthorization() async throws -> PermissionStatus
}

public extension PermissionProvider {
    func resolvedStatus() async -> PermissionStatus {
        currentStatus()
    }
}
