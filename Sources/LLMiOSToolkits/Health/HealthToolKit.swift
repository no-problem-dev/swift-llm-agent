#if canImport(HealthKit)
import Foundation
import HealthKit
import LLMClient
import LLMTool
import LLMMCP

// MARK: - HealthToolKit

/// ヘルスデータを操作する ToolKit
///
/// HealthKit を使用して、歩数・心拍・睡眠等のクエリ、
/// サマリー取得、ワークアウト履歴、データ記録を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     HealthToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `query_health_data`: 特定のヘルスデータを期間指定でクエリ
/// - `get_health_summary`: 今日/今週のヘルスサマリー
/// - `query_workouts`: ワークアウト履歴の検索
/// - `save_health_data`: 体重等のデータを手動記録
///
/// ## 注意事項
///
/// iPad では HealthKit が利用できません。
public final class HealthToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "health"

    private let healthStore: HKHealthStore
    private let guard_: PermissionGuard

    // MARK: - Initialization

    public init() {
        self.healthStore = HKHealthStore()
        self.guard_ = PermissionGuard(
            provider: HealthPermission(
                healthStore: healthStore,
                readTypes: HealthDataTypes.defaultReadTypes,
                writeTypes: HealthDataTypes.defaultWriteTypes
            )
        )
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            queryHealthDataTool,
            getHealthSummaryTool,
            queryWorkoutsTool,
            saveHealthDataTool,
        ]
    }

    // MARK: - query_health_data

    private var queryHealthDataTool: BuiltInTool {
        BuiltInTool(
            name: "query_health_data",
            description: "Query health data for a specific type and date range. "
                + "Returns aggregated statistics (sum, average, min, max). "
                + "Available data types: steps, heart_rate, distance, active_energy, body_mass, sleep.",
            inputSchema: .object(
                properties: [
                    "data_type": .string(
                        description: "Health data type: 'steps', 'heart_rate', 'distance', 'active_energy', 'body_mass', 'sleep'"
                    ),
                    "start_date": .string(
                        description: "Start date in ISO8601 format (e.g., '2025-03-01T00:00:00+09:00')"
                    ),
                    "end_date": .string(
                        description: "End date in ISO8601 format (e.g., '2025-03-07T23:59:59+09:00')"
                    ),
                    "aggregation": .string(
                        description: "Aggregation type: 'sum' (default for steps/distance/energy), 'average' (default for heart_rate/body_mass), 'min', 'max'"
                    ),
                ],
                required: ["data_type", "start_date", "end_date"]
            ),
            annotations: ToolAnnotations(
                title: "Query Health Data",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(QueryHealthDataInput.self, from: data)

            guard let start = CalendarDateHelper.parseDate(input.startDate) else {
                return .error("Invalid start_date format.")
            }
            guard let end = CalendarDateHelper.parseDate(input.endDate) else {
                return .error("Invalid end_date format.")
            }

            guard let (quantityType, unit, defaultAgg) = Self.resolveDataType(input.dataType) else {
                return .error(
                    "Unknown data type: '\(input.dataType)'. "
                    + "Available types: steps, heart_rate, distance, active_energy, body_mass, sleep."
                )
            }

            let aggregation = input.aggregation ?? defaultAgg
            let predicate = HKQuery.predicateForSamples(
                withStart: start, end: end, options: .strictStartDate
            )

            do {
                let value = try await Self.queryStatistics(
                    healthStore: healthStore,
                    quantityType: quantityType,
                    predicate: predicate,
                    aggregation: aggregation,
                    unit: unit
                )

                let result = HealthDataResult(
                    dataType: input.dataType,
                    startDate: CalendarDateHelper.formatDate(start),
                    endDate: CalendarDateHelper.formatDate(end),
                    aggregation: aggregation,
                    value: value,
                    unit: unit.unitString
                )
                return try .encoded(result)
            } catch {
                return .error("Failed to query health data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - get_health_summary

    private var getHealthSummaryTool: BuiltInTool {
        BuiltInTool(
            name: "get_health_summary",
            description: "Get a summary of health data for today or this week. "
                + "Includes steps, distance, active energy, average heart rate, and sleep hours.",
            inputSchema: .object(
                properties: [
                    "period": .string(
                        description: "Period: 'today' (default) or 'week'"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Health Summary",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(GetHealthSummaryInput.self, from: data)
            let period = input.period?.lowercased() ?? "today"

            let calendar = Calendar.current
            let now = Date()
            let start: Date
            let end: Date

            if period == "week" {
                start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
                end = now
            } else {
                start = calendar.startOfDay(for: now)
                end = now
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: start, end: end, options: .strictStartDate
            )

            let steps = try? await Self.queryStatistics(
                healthStore: healthStore,
                quantityType: HKQuantityType(.stepCount),
                predicate: predicate,
                aggregation: "sum",
                unit: .count()
            )

            let distance = try? await Self.queryStatistics(
                healthStore: healthStore,
                quantityType: HKQuantityType(.distanceWalkingRunning),
                predicate: predicate,
                aggregation: "sum",
                unit: .meterUnit(with: .kilo)
            )

            let energy = try? await Self.queryStatistics(
                healthStore: healthStore,
                quantityType: HKQuantityType(.activeEnergyBurned),
                predicate: predicate,
                aggregation: "sum",
                unit: .kilocalorie()
            )

            let heartRate = try? await Self.queryStatistics(
                healthStore: healthStore,
                quantityType: HKQuantityType(.heartRate),
                predicate: predicate,
                aggregation: "average",
                unit: HKUnit.count().unitDivided(by: .minute())
            )

            let summary = HealthSummary(
                period: period,
                startDate: CalendarDateHelper.formatDate(start),
                endDate: CalendarDateHelper.formatDate(end),
                steps: steps.map { ($0 * 10).rounded() / 10 },
                distance: distance.map { ($0 * 100).rounded() / 100 },
                activeEnergy: energy.map { ($0 * 10).rounded() / 10 },
                heartRateAvg: heartRate.map { ($0 * 10).rounded() / 10 },
                sleepHours: nil
            )

            return try .encoded(summary)
        }
    }

    // MARK: - query_workouts

    private var queryWorkoutsTool: BuiltInTool {
        BuiltInTool(
            name: "query_workouts",
            description: "Query workout history. Returns workouts with type, duration, distance, and calories.",
            inputSchema: .object(
                properties: [
                    "start_date": .string(description: "Start date in ISO8601 format"),
                    "end_date": .string(description: "End date in ISO8601 format"),
                    "workout_type": .string(
                        description: "Filter by workout type: 'running', 'walking', 'cycling', 'swimming', 'yoga', etc."
                    ),
                    "limit": .integer(description: "Maximum results (default: 20, max: 100)"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Query Workouts",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(QueryWorkoutsInput.self, from: data)
            let limit = min(input.limit ?? 20, 100)

            let start = input.startDate.flatMap { CalendarDateHelper.parseDate($0) }
                ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            let end = input.endDate.flatMap { CalendarDateHelper.parseDate($0) }
                ?? Date()

            var predicates: [NSPredicate] = [
                HKQuery.predicateForSamples(
                    withStart: start, end: end, options: .strictStartDate
                )
            ]

            if let workoutTypeStr = input.workoutType,
               let activityType = Self.resolveWorkoutType(workoutTypeStr) {
                predicates.append(
                    HKQuery.predicateForWorkouts(with: activityType)
                )
            }

            let compound = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let workouts: [WorkoutInfo] = try await withCheckedThrowingContinuation { continuation in
                let sort = NSSortDescriptor(
                    key: HKSampleSortIdentifierStartDate,
                    ascending: false
                )
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: compound,
                    limit: limit,
                    sortDescriptors: [sort]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let infos = (results as? [HKWorkout] ?? []).map { workout -> WorkoutInfo in
                        let duration = workout.duration
                        let minutes = Int(duration) / 60
                        let hours = minutes / 60
                        let remainingMins = minutes % 60
                        let durationText = hours > 0
                            ? "\(hours)h \(remainingMins)min" : "\(minutes)min"

                        return WorkoutInfo(
                            workoutType: workout.workoutActivityType.name,
                            startDate: CalendarDateHelper.formatDate(workout.startDate),
                            endDate: CalendarDateHelper.formatDate(workout.endDate),
                            duration: duration,
                            durationText: durationText,
                            totalDistance: workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                            totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                        )
                    }
                    continuation.resume(returning: infos)
                }
                healthStore.execute(query)
            }

            return try .encoded(workouts)
        }
    }

    // MARK: - save_health_data

    private var saveHealthDataTool: BuiltInTool {
        BuiltInTool(
            name: "save_health_data",
            description: "Save a health data point. Currently supports: body_mass (weight). "
                + "IMPORTANT: Use the user's local time.",
            inputSchema: .object(
                properties: [
                    "data_type": .string(
                        description: "Data type to save: 'body_mass'"
                    ),
                    "value": .number(description: "Value to record"),
                    "unit": .string(
                        description: "Unit: 'kg' (default) or 'lb' for body_mass"
                    ),
                    "date": .string(
                        description: "Date of measurement in ISO8601 (default: now)"
                    ),
                ],
                required: ["data_type", "value"]
            ),
            annotations: ToolAnnotations(
                title: "Save Health Data",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SaveHealthDataInput.self, from: data)

            guard input.dataType == "body_mass" else {
                return .error(
                    "Currently only 'body_mass' is supported for saving. "
                    + "Other data types may be added in the future."
                )
            }

            let unit: HKUnit = (input.unit?.lowercased() == "lb")
                ? .pound() : .gramUnit(with: .kilo)
            let unitString = (input.unit?.lowercased() == "lb") ? "lb" : "kg"

            let date = input.date.flatMap { CalendarDateHelper.parseDate($0) } ?? Date()
            let quantityType = HKQuantityType(.bodyMass)
            let quantity = HKQuantity(unit: unit, doubleValue: input.value)
            let sample = HKQuantitySample(
                type: quantityType,
                quantity: quantity,
                start: date,
                end: date
            )

            do {
                try await healthStore.save(sample)
                let result = SaveHealthDataResult(
                    dataType: input.dataType,
                    value: input.value,
                    unit: unitString,
                    date: CalendarDateHelper.formatDate(date)
                )
                return try .encoded(result)
            } catch {
                return .error("Failed to save health data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func resolveDataType(_ name: String) -> (HKQuantityType, HKUnit, String)? {
        switch name.lowercased() {
        case "steps", "step_count":
            return (HKQuantityType(.stepCount), .count(), "sum")
        case "heart_rate":
            return (HKQuantityType(.heartRate), HKUnit.count().unitDivided(by: .minute()), "average")
        case "distance", "walking_distance":
            return (HKQuantityType(.distanceWalkingRunning), .meterUnit(with: .kilo), "sum")
        case "active_energy", "calories":
            return (HKQuantityType(.activeEnergyBurned), .kilocalorie(), "sum")
        case "body_mass", "weight":
            return (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), "average")
        default:
            return nil
        }
    }

    private static func queryStatistics(
        healthStore: HKHealthStore,
        quantityType: HKQuantityType,
        predicate: NSPredicate,
        aggregation: String,
        unit: HKUnit
    ) async throws -> Double? {
        let options: HKStatisticsOptions
        switch aggregation {
        case "sum":
            options = .cumulativeSum
        case "average":
            options = .discreteAverage
        case "min":
            options = .discreteMin
        case "max":
            options = .discreteMax
        default:
            options = .cumulativeSum
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value: Double?
                switch aggregation {
                case "sum":
                    value = statistics?.sumQuantity()?.doubleValue(for: unit)
                case "average":
                    value = statistics?.averageQuantity()?.doubleValue(for: unit)
                case "min":
                    value = statistics?.minimumQuantity()?.doubleValue(for: unit)
                case "max":
                    value = statistics?.maximumQuantity()?.doubleValue(for: unit)
                default:
                    value = statistics?.sumQuantity()?.doubleValue(for: unit)
                }
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private static func resolveWorkoutType(_ name: String) -> HKWorkoutActivityType? {
        switch name.lowercased() {
        case "running", "run":
            return .running
        case "walking", "walk":
            return .walking
        case "cycling", "bike", "bicycle":
            return .cycling
        case "swimming", "swim":
            return .swimming
        case "yoga":
            return .yoga
        case "hiking", "hike":
            return .hiking
        case "dance", "dancing":
            return .dance
        case "strength", "weight_training":
            return .traditionalStrengthTraining
        case "pilates":
            return .pilates
        case "elliptical":
            return .elliptical
        default:
            return nil
        }
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .yoga: return "yoga"
        case .hiking: return "hiking"
        case .dance: return "dance"
        case .traditionalStrengthTraining: return "strength_training"
        case .pilates: return "pilates"
        case .elliptical: return "elliptical"
        default: return "other"
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// HealthKit 非対応プラットフォーム用のスタブ
public final class HealthToolKit: ToolKit, Sendable {
    public let name: String = "health"
    public init() {}
    public var tools: [any Tool] { [] }
}
#endif
