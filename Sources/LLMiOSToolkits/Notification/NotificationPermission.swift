import Foundation
import UserNotifications

/// UserNotifications 用の PermissionProvider
struct NotificationPermission: PermissionProvider, Sendable {
    var permissionName: String { "Notifications" }
    var settingsPath: String { "Notifications" }

    func currentStatus() -> PermissionStatus {
        // UNUserNotificationCenter の status は async のため、
        // ここでは .notDetermined を返して requestAuthorization に委ねる
        // 実際の判定は requestAuthorization 内で行う
        .notDetermined
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted ? .authorized : .denied
        @unknown default:
            return .denied
        }
    }
}
