@preconcurrency import EventKit
import Foundation

/// EventKit イベント用の PermissionProvider
struct CalendarEventPermission: PermissionProvider, @unchecked Sendable {
    let eventStore: EKEventStore

    var permissionName: String { "Calendar Events" }
    var settingsPath: String { "Calendars" }

    func currentStatus() -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .writeOnly:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let granted = try await eventStore.requestFullAccessToEvents()
        return granted ? .authorized : .denied
    }
}

/// EventKit リマインダー用の PermissionProvider
struct CalendarReminderPermission: PermissionProvider, @unchecked Sendable {
    let eventStore: EKEventStore

    var permissionName: String { "Reminders" }
    var settingsPath: String { "Reminders" }

    func currentStatus() -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let granted = try await eventStore.requestFullAccessToReminders()
        return granted ? .authorized : .denied
    }
}
