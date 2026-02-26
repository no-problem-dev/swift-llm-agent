@preconcurrency import CoreLocation
import Foundation
import os

/// CLLocationManagerDelegate → AsyncStream ブリッジ
///
/// CLLocationManager のデリゲートコールバックを AsyncStream に変換する。
/// 認可状態の変更と位置情報の取得をそれぞれ独立したストリームとして提供。
///
/// `withCheckedContinuation` ではなく `AsyncStream` を使用する理由:
/// - デリゲートコールバックは複数回呼ばれる可能性がある（continuation は2回 resume するとクラッシュ）
/// - デリゲートコールバックが呼ばれない可能性がある（continuation は永久にサスペンド）
/// - AsyncStream なら複数回 yield しても安全で、タイムアウトとも組み合わせやすい
///
/// ## 使い方
///
/// ```swift
/// let delegate = LocationManagerDelegate()
/// locationManager.delegate = delegate
///
/// // 認可の待機
/// let stream = delegate.authorizationStream()
/// locationManager.requestWhenInUseAuthorization()
/// for await status in stream { ... }
///
/// // 位置情報の取得
/// let stream = delegate.locationStream()
/// locationManager.requestLocation()
/// for await result in stream { ... }
/// ```
final class LocationManagerDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    // MARK: - State

    private struct State {
        var authorizationContinuation: AsyncStream<CLAuthorizationStatus>.Continuation?
        var locationContinuation: AsyncStream<Result<CLLocation, Error>>.Continuation?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Authorization Stream

    /// 認可状態の変更を監視するストリームを作成
    ///
    /// 既存のストリームがある場合は finish してから新規作成する。
    /// `requestWhenInUseAuthorization()` を呼ぶ前にストリームを作成すること。
    func authorizationStream() -> AsyncStream<CLAuthorizationStatus> {
        // finish() は onTermination を同期呼び出しするため、ロック外で実行
        let previous = state.withLock { state -> AsyncStream<CLAuthorizationStatus>.Continuation? in
            let cont = state.authorizationContinuation
            state.authorizationContinuation = nil
            return cont
        }
        previous?.finish()

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.authorizationContinuation = nil }
            }
            self.state.withLock { $0.authorizationContinuation = continuation }
        }
    }

    // MARK: - Location Stream

    /// 位置情報を取得するストリームを作成
    ///
    /// 既存のストリームがある場合は finish してから新規作成する。
    /// `requestLocation()` を呼ぶ前にストリームを作成すること。
    func locationStream() -> AsyncStream<Result<CLLocation, Error>> {
        // finish() は onTermination を同期呼び出しするため、ロック外で実行
        let previous = state.withLock { state -> AsyncStream<Result<CLLocation, Error>>.Continuation? in
            let cont = state.locationContinuation
            state.locationContinuation = nil
            return cont
        }
        previous?.finish()

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.locationContinuation = nil }
            }
            self.state.withLock { $0.locationContinuation = continuation }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        state.withLock { _ = $0.authorizationContinuation?.yield(status) }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        // yield は安全（戻り値を捨てるだけ）だがfinish() はロック外で実行
        let continuation = state.withLock { state -> AsyncStream<Result<CLLocation, Error>>.Continuation? in
            let cont = state.locationContinuation
            state.locationContinuation = nil
            return cont
        }
        continuation?.yield(.success(location))
        continuation?.finish()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let continuation = state.withLock { state -> AsyncStream<Result<CLLocation, Error>>.Continuation? in
            let cont = state.locationContinuation
            state.locationContinuation = nil
            return cont
        }
        continuation?.yield(.failure(error))
        continuation?.finish()
    }
}
