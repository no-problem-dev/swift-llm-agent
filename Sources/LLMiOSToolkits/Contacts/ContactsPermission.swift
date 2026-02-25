@preconcurrency import Contacts
import Foundation

/// Contacts フレームワーク用の PermissionProvider
struct ContactsPermission: PermissionProvider, Sendable {
    let contactStore: CNContactStore

    var permissionName: String { "Contacts" }
    var settingsPath: String { "Contacts" }

    func currentStatus() -> PermissionStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .limited:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> PermissionStatus {
        let granted = try await contactStore.requestAccess(for: .contacts)
        return granted ? .authorized : .denied
    }
}
