@preconcurrency import CoreLocation
import Foundation

/// CoreLocation 用の PermissionProvider
///
/// `LocationManagerDelegate` の `authorizationStream()` を使って
/// 認可状態の変更を非同期に待機する。
/// `Task.sleep` による脆弱な待機ではなく、デリゲートコールバックを
/// AsyncStream で確実にブリッジする。
final class LocationPermission: PermissionProvider, @unchecked Sendable {
    private let locationManager: CLLocationManager
    private let delegate: LocationManagerDelegate
    private let timeoutDuration: Duration

    var permissionName: String { "Location" }
    var settingsPath: String { "Location Services" }

    init(
        locationManager: CLLocationManager,
        delegate: LocationManagerDelegate,
        timeout: Duration = .seconds(30)
    ) {
        self.locationManager = locationManager
        self.delegate = delegate
        self.timeoutDuration = timeout
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
        let current = currentStatus()
        if current != .notDetermined { return current }

        // ストリームを作成してからリクエストを発行
        let stream = delegate.authorizationStream()

        await MainActor.run {
            locationManager.requestWhenInUseAuthorization()
        }

        // stream 待機 vs タイムアウトをレース
        return try await withThrowingTaskGroup(of: PermissionStatus.self) { group in
            group.addTask {
                for await status in stream {
                    switch status {
                    case .authorizedWhenInUse, .authorizedAlways:
                        return .authorized
                    case .denied:
                        return .denied
                    case .restricted:
                        return .restricted
                    case .notDetermined:
                        // 初期コールバックをスキップ、ユーザーの応答を待つ
                        continue
                    @unknown default:
                        return .denied
                    }
                }
                // ストリームが確定ステータスなしで終了
                return .denied
            }

            group.addTask { [timeoutDuration] in
                try await Task.sleep(for: timeoutDuration)
                throw LocationError.authorizationTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
