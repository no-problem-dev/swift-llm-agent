@preconcurrency import CoreLocation
import Foundation

/// CoreLocation 用の PermissionProvider
final class LocationPermission: PermissionProvider, @unchecked Sendable {
    private let locationManager: CLLocationManager

    var permissionName: String { "Location" }
    var settingsPath: String { "Location Services" }

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
    }

    func currentStatus() -> PermissionStatus {
        guard CLLocationManager.locationServicesEnabled() else {
            return .restricted
        }
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
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
        locationManager.requestWhenInUseAuthorization()
        // 権限リクエストは非同期のため、少し待ってから状態を返す
        // 実際にはアプリ側で CLLocationManagerDelegate を使うことが推奨される
        try await Task.sleep(for: .milliseconds(500))
        return currentStatus()
    }
}
