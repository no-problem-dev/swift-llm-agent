#if canImport(HealthKit)
import Foundation
import HealthKit

/// HealthKit 用の PermissionProvider
///
/// HealthKit はデータ型ごとに個別の認可が必要。
/// ここでは読み取りのみの基本的なヘルスデータ型を要求する。
struct HealthPermission: PermissionProvider, @unchecked Sendable {
    let healthStore: HKHealthStore

    /// 読み取り対象のデータ型
    let readTypes: Set<HKObjectType>
    /// 書き込み対象のデータ型
    let writeTypes: Set<HKSampleType>

    var permissionName: String { "Health" }
    var settingsPath: String { "Health" }

    func currentStatus() -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .restricted
        }
        // HealthKit は個別のデータ型ごとの認可のため、
        // まとめて判定することが難しい → notDetermined として毎回リクエストに委ねる
        return .notDetermined
    }

    func requestAuthorization() async throws -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .restricted
        }
        try await healthStore.requestAuthorization(
            toShare: writeTypes,
            read: readTypes
        )
        // HealthKit は requestAuthorization が成功しても
        // 個別のデータ型へのアクセスが拒否されている場合がある。
        // ここでは一律 authorized として返し、個別クエリでエラーを処理する。
        return .authorized
    }
}

/// デフォルトの HealthKit データ型セット
enum HealthDataTypes {
    /// 読み取り用のデータ型
    static var defaultReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        // 歩数
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        // 心拍数
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        // 歩行距離
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        // アクティブエネルギー
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        // 体重
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        // 睡眠分析
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        // ワークアウト
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// 書き込み用のデータ型
    static var defaultWriteTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let bodyMass = HKSampleType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        return types
    }
}
#endif
