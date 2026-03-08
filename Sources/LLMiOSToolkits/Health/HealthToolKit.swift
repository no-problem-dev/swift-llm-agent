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
/// - `query_sleep`: 睡眠データの詳細クエリ（ステージ別分析付き）
/// - `query_workouts`: ワークアウト履歴の検索
/// - `query_mindfulness`: マインドフルネスセッションの検索
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
            querySleepTool,
            queryWorkoutsTool,
            queryMindfulnessTool,
            saveHealthDataTool,
        ]
    }

    // MARK: - query_health_data

    private var queryHealthDataTool: BuiltInTool {
        BuiltInTool(
            name: "query_health_data",
            description: "Query health data for a specific type and date range. "
                + "Returns aggregated statistics. "
                + "Available data types: "
                + "Activity: steps, distance, active_energy, basal_energy, flights_climbed, exercise_time, stand_time. "
                + "Heart: heart_rate, resting_heart_rate, hrv, walking_heart_rate_avg, vo2_max. "
                + "Body: body_mass, bmi, body_fat, height. "
                + "Vitals: oxygen_saturation, body_temperature, respiratory_rate, blood_pressure_systolic, blood_pressure_diastolic. "
                + "Audio: environmental_audio, headphone_audio. "
                + "NOTE: For sleep data use query_sleep, for mindfulness use query_mindfulness.",
            inputSchema: .object(
                properties: [
                    "data_type": .string(
                        description: "Health data type (see description for available types)"
                    ),
                    "start_date": .string(
                        description: "Start date in ISO8601 format (e.g., '2025-03-01T00:00:00+09:00')"
                    ),
                    "end_date": .string(
                        description: "End date in ISO8601 format (e.g., '2025-03-07T23:59:59+09:00')"
                    ),
                    "aggregation": .string(
                        description: "Aggregation type: 'sum' (for cumulative types like steps/distance/energy), "
                            + "'average', 'min', 'max' (for discrete types like heart_rate/body_mass). "
                            + "If omitted, the appropriate default for the data type is used."
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

            guard let resolved = Self.resolveQuantityType(input.dataType) else {
                return .error(
                    "Unknown or unsupported data type: '\(input.dataType)'. "
                    + "For sleep data use query_sleep tool. "
                    + "For mindfulness use query_mindfulness tool. "
                    + "Available types: steps, heart_rate, distance, active_energy, basal_energy, "
                    + "flights_climbed, exercise_time, stand_time, resting_heart_rate, hrv, "
                    + "walking_heart_rate_avg, vo2_max, body_mass, bmi, body_fat, height, "
                    + "oxygen_saturation, body_temperature, respiratory_rate, "
                    + "blood_pressure_systolic, blood_pressure_diastolic, "
                    + "environmental_audio, headphone_audio."
                )
            }

            let (quantityType, unit, defaultAgg, aggStyle) = resolved
            let requestedAgg = input.aggregation ?? defaultAgg

            // aggregation バリデーション
            if let validationError = Self.validateAggregation(
                aggregation: requestedAgg, style: aggStyle, dataType: input.dataType
            ) {
                return .error(validationError)
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: start, end: end, options: .strictStartDate
            )

            do {
                let value = try await Self.queryStatistics(
                    healthStore: healthStore,
                    quantityType: quantityType,
                    predicate: predicate,
                    aggregation: requestedAgg,
                    unit: unit
                )

                let result = HealthDataResult(
                    dataType: input.dataType,
                    startDate: CalendarDateHelper.formatDate(start),
                    endDate: CalendarDateHelper.formatDate(end),
                    aggregation: requestedAgg,
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
                + "Includes steps, distance, active energy, average heart rate, and sleep analysis.",
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

            // 睡眠データ取得（前日21時〜現在を対象範囲とする）
            let sleepStart: Date
            if period == "week" {
                sleepStart = start
            } else {
                // 今日のサマリー: 前日21時から
                sleepStart = calendar.date(
                    bySettingHour: 21, minute: 0, second: 0,
                    of: calendar.date(byAdding: .day, value: -1, to: now)!
                )!
            }
            let sleepSummary = try? await Self.querySleepAnalysis(
                healthStore: healthStore,
                start: sleepStart,
                end: end
            )
            let sleepHours = sleepSummary.map { $0.totalSleepMinutes / 60.0 }

            let summary = HealthSummary(
                period: period,
                startDate: CalendarDateHelper.formatDate(start),
                endDate: CalendarDateHelper.formatDate(end),
                steps: steps.map { ($0 * 10).rounded() / 10 },
                distance: distance.map { ($0 * 100).rounded() / 100 },
                activeEnergy: energy.map { ($0 * 10).rounded() / 10 },
                heartRateAvg: heartRate.map { ($0 * 10).rounded() / 10 },
                sleepHours: sleepHours.map { ($0 * 100).rounded() / 100 },
                sleepDetails: sleepSummary
            )

            return try .encoded(summary)
        }
    }

    // MARK: - query_sleep

    private var querySleepTool: BuiltInTool {
        BuiltInTool(
            name: "query_sleep",
            description: "Query detailed sleep analysis data. "
                + "Returns sleep stages (inBed, asleepCore, asleepDeep, asleepREM, awake) with duration for each session. "
                + "Also provides aggregated summary with total sleep time and sleep efficiency. "
                + "TIP: For last night's sleep, set start_date to yesterday 21:00 and end_date to today's current time.",
            inputSchema: .object(
                properties: [
                    "start_date": .string(
                        description: "Start date in ISO8601 format (e.g., '2025-03-06T21:00:00+09:00')"
                    ),
                    "end_date": .string(
                        description: "End date in ISO8601 format (e.g., '2025-03-07T12:00:00+09:00')"
                    ),
                ],
                required: ["start_date", "end_date"]
            ),
            annotations: ToolAnnotations(
                title: "Query Sleep Data",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(QuerySleepInput.self, from: data)

            guard let start = CalendarDateHelper.parseDate(input.startDate) else {
                return .error("Invalid start_date format.")
            }
            guard let end = CalendarDateHelper.parseDate(input.endDate) else {
                return .error("Invalid end_date format.")
            }

            do {
                let summary = try await Self.querySleepAnalysis(
                    healthStore: healthStore, start: start, end: end
                )
                let sessions = try await Self.querySleepSessions(
                    healthStore: healthStore, start: start, end: end
                )

                let result = SleepAnalysisResult(
                    startDate: CalendarDateHelper.formatDate(start),
                    endDate: CalendarDateHelper.formatDate(end),
                    summary: summary,
                    sessions: sessions
                )
                return try .encoded(result)
            } catch {
                return .error("Failed to query sleep data: \(error.localizedDescription)")
            }
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
                        description: "Filter by workout type: 'running', 'walking', 'cycling', 'swimming', 'yoga', 'hiking', 'dance', 'strength', 'pilates', 'elliptical', 'core_training', 'functional_training', 'mixed_cardio', 'stair_climbing', 'tennis', 'badminton', 'table_tennis', 'soccer', 'basketball'"
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

    // MARK: - query_mindfulness

    private var queryMindfulnessTool: BuiltInTool {
        BuiltInTool(
            name: "query_mindfulness",
            description: "Query mindfulness/meditation session history. "
                + "Returns individual sessions with duration and total minutes.",
            inputSchema: .object(
                properties: [
                    "start_date": .string(description: "Start date in ISO8601 format"),
                    "end_date": .string(description: "End date in ISO8601 format"),
                    "limit": .integer(description: "Maximum results (default: 50, max: 200)"),
                ],
                required: ["start_date", "end_date"]
            ),
            annotations: ToolAnnotations(
                title: "Query Mindfulness",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [healthStore, guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(QueryMindfulnessInput.self, from: data)

            guard let start = CalendarDateHelper.parseDate(input.startDate) else {
                return .error("Invalid start_date format.")
            }
            guard let end = CalendarDateHelper.parseDate(input.endDate) else {
                return .error("Invalid end_date format.")
            }

            let limit = min(input.limit ?? 50, 200)

            do {
                let sessions = try await Self.queryCategorySamples(
                    healthStore: healthStore,
                    categoryType: HKCategoryType(.mindfulSession),
                    start: start,
                    end: end,
                    limit: limit
                )

                let mindfulSessions = sessions.map { sample -> MindfulnessSession in
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    return MindfulnessSession(
                        startDate: CalendarDateHelper.formatDate(sample.startDate),
                        endDate: CalendarDateHelper.formatDate(sample.endDate),
                        durationMinutes: (duration * 10).rounded() / 10
                    )
                }

                let totalMinutes = sessions.reduce(0.0) { acc, sample in
                    acc + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                }

                let result = MindfulnessResult(
                    startDate: CalendarDateHelper.formatDate(start),
                    endDate: CalendarDateHelper.formatDate(end),
                    totalMinutes: (totalMinutes * 10).rounded() / 10,
                    sessionCount: sessions.count,
                    sessions: mindfulSessions
                )
                return try .encoded(result)
            } catch {
                return .error("Failed to query mindfulness data: \(error.localizedDescription)")
            }
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

    // MARK: - Data Type Resolution

    /// QuantityType のデータ型を解決する
    /// Returns: (quantityType, unit, defaultAggregation, aggregationStyle)
    private static func resolveQuantityType(_ name: String) -> (HKQuantityType, HKUnit, String, AggregationStyle)? {
        switch name.lowercased() {
        // Activity (cumulative)
        case "steps", "step_count":
            return (HKQuantityType(.stepCount), .count(), "sum", .cumulative)
        case "distance", "walking_distance":
            return (HKQuantityType(.distanceWalkingRunning), .meterUnit(with: .kilo), "sum", .cumulative)
        case "active_energy", "calories":
            return (HKQuantityType(.activeEnergyBurned), .kilocalorie(), "sum", .cumulative)
        case "basal_energy":
            return (HKQuantityType(.basalEnergyBurned), .kilocalorie(), "sum", .cumulative)
        case "flights_climbed", "flights":
            return (HKQuantityType(.flightsClimbed), .count(), "sum", .cumulative)
        case "exercise_time":
            return (HKQuantityType(.appleExerciseTime), .minute(), "sum", .cumulative)
        case "stand_time":
            return (HKQuantityType(.appleStandTime), .minute(), "sum", .cumulative)
        case "cycling_distance":
            return (HKQuantityType(.distanceCycling), .meterUnit(with: .kilo), "sum", .cumulative)
        case "swimming_distance":
            return (HKQuantityType(.distanceSwimming), .meter(), "sum", .cumulative)

        // Heart (discrete)
        case "heart_rate":
            return (HKQuantityType(.heartRate), HKUnit.count().unitDivided(by: .minute()), "average", .discrete)
        case "resting_heart_rate":
            return (HKQuantityType(.restingHeartRate), HKUnit.count().unitDivided(by: .minute()), "average", .discrete)
        case "hrv", "heart_rate_variability":
            return (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli), "average", .discrete)
        case "walking_heart_rate_avg", "walking_heart_rate":
            return (HKQuantityType(.walkingHeartRateAverage), HKUnit.count().unitDivided(by: .minute()), "average", .discrete)
        case "vo2_max":
            return (HKQuantityType(.vo2Max), HKUnit(from: "mL/kg*min"), "average", .discrete)

        // Body (discrete)
        case "body_mass", "weight":
            return (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), "average", .discrete)
        case "bmi", "body_mass_index":
            return (HKQuantityType(.bodyMassIndex), .count(), "average", .discrete)
        case "body_fat", "body_fat_percentage":
            return (HKQuantityType(.bodyFatPercentage), .percent(), "average", .discrete)
        case "height":
            return (HKQuantityType(.height), .meterUnit(with: .centi), "average", .discrete)

        // Vitals (discrete)
        case "oxygen_saturation", "spo2":
            return (HKQuantityType(.oxygenSaturation), .percent(), "average", .discrete)
        case "body_temperature", "temperature":
            return (HKQuantityType(.bodyTemperature), .degreeCelsius(), "average", .discrete)
        case "respiratory_rate", "breathing_rate":
            return (HKQuantityType(.respiratoryRate), HKUnit.count().unitDivided(by: .minute()), "average", .discrete)
        case "blood_pressure_systolic":
            return (HKQuantityType(.bloodPressureSystolic), .millimeterOfMercury(), "average", .discrete)
        case "blood_pressure_diastolic":
            return (HKQuantityType(.bloodPressureDiastolic), .millimeterOfMercury(), "average", .discrete)
        case "blood_glucose":
            return (HKQuantityType(.bloodGlucose), HKUnit(from: "mg/dL"), "average", .discrete)

        // Audio (discrete)
        case "environmental_audio", "environmental_audio_exposure":
            return (HKQuantityType(.environmentalAudioExposure), .decibelAWeightedSoundPressureLevel(), "average", .discrete)
        case "headphone_audio", "headphone_audio_exposure":
            return (HKQuantityType(.headphoneAudioExposure), .decibelAWeightedSoundPressureLevel(), "average", .discrete)

        default:
            return nil
        }
    }

    // MARK: - Aggregation

    enum AggregationStyle {
        case cumulative
        case discrete
    }

    /// aggregation と dataType の組み合わせをバリデーション
    private static func validateAggregation(
        aggregation: String, style: AggregationStyle, dataType: String
    ) -> String? {
        switch style {
        case .cumulative:
            if aggregation == "average" || aggregation == "min" || aggregation == "max" {
                return "'\(dataType)' is a cumulative type. "
                    + "Only 'sum' aggregation is supported. "
                    + "Use aggregation: 'sum' or omit the aggregation parameter."
            }
        case .discrete:
            if aggregation == "sum" {
                return "'\(dataType)' is a discrete type. "
                    + "'sum' aggregation is not supported. "
                    + "Use 'average', 'min', or 'max' instead."
            }
        }
        return nil
    }

    // MARK: - Statistics Query

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

    // MARK: - Sleep Analysis (CategoryType)

    /// 睡眠データのサマリーを取得
    private static func querySleepAnalysis(
        healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> SleepSummary {
        let samples = try await querySleepCategorySamples(
            healthStore: healthStore, start: start, end: end
        )

        var inBedMinutes: Double = 0
        var asleepUnspecifiedMinutes: Double = 0
        var coreSleepMinutes: Double = 0
        var deepSleepMinutes: Double = 0
        var remSleepMinutes: Double = 0
        var awakeMinutes: Double = 0

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            guard let stage = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }

            switch stage {
            case .inBed:
                inBedMinutes += duration
            case .asleepUnspecified:
                asleepUnspecifiedMinutes += duration
            case .asleepCore:
                coreSleepMinutes += duration
            case .asleepDeep:
                deepSleepMinutes += duration
            case .asleepREM:
                remSleepMinutes += duration
            case .awake:
                awakeMinutes += duration
            @unknown default:
                break
            }
        }

        let totalSleep = asleepUnspecifiedMinutes + coreSleepMinutes + deepSleepMinutes + remSleepMinutes
        let hasStageData = coreSleepMinutes > 0 || deepSleepMinutes > 0 || remSleepMinutes > 0
        let sleepEfficiency: Double? = inBedMinutes > 0
            ? (totalSleep / inBedMinutes * 100).rounded() / 1 : nil

        return SleepSummary(
            totalSleepMinutes: (totalSleep * 10).rounded() / 10,
            inBedMinutes: (inBedMinutes * 10).rounded() / 10,
            coreSleepMinutes: hasStageData ? (coreSleepMinutes * 10).rounded() / 10 : nil,
            deepSleepMinutes: hasStageData ? (deepSleepMinutes * 10).rounded() / 10 : nil,
            remSleepMinutes: hasStageData ? (remSleepMinutes * 10).rounded() / 10 : nil,
            awakeMinutes: awakeMinutes > 0 ? (awakeMinutes * 10).rounded() / 10 : nil,
            sleepEfficiency: sleepEfficiency
        )
    }

    /// 睡眠データの個別セッションを取得
    private static func querySleepSessions(
        healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [SleepSession] {
        let samples = try await querySleepCategorySamples(
            healthStore: healthStore, start: start, end: end
        )

        return samples.compactMap { sample -> SleepSession? in
            guard let stage = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0

            let stageName: String
            switch stage {
            case .inBed: stageName = "inBed"
            case .asleepUnspecified: stageName = "asleep"
            case .asleepCore: stageName = "asleepCore"
            case .asleepDeep: stageName = "asleepDeep"
            case .asleepREM: stageName = "asleepREM"
            case .awake: stageName = "awake"
            @unknown default: stageName = "unknown"
            }

            return SleepSession(
                stage: stageName,
                startDate: CalendarDateHelper.formatDate(sample.startDate),
                endDate: CalendarDateHelper.formatDate(sample.endDate),
                durationMinutes: (duration * 10).rounded() / 10
            )
        }
    }

    /// HKCategorySample を HKSampleQuery で取得する汎用メソッド
    private static func querySleepCategorySamples(
        healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = results as? [HKCategorySample] ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.execute(query)
        }
    }

    /// HKCategorySample を汎用的に取得するメソッド
    private static func queryCategorySamples(
        healthStore: HKHealthStore,
        categoryType: HKCategoryType,
        start: Date,
        end: Date,
        limit: Int
    ) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = results as? [HKCategorySample] ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Workout Type Resolution

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
        case "strength", "weight_training", "strength_training":
            return .traditionalStrengthTraining
        case "pilates":
            return .pilates
        case "elliptical":
            return .elliptical
        case "core_training", "core":
            return .coreTraining
        case "functional_training", "functional":
            return .functionalStrengthTraining
        case "mixed_cardio", "cardio":
            return .mixedCardio
        case "stair_climbing", "stair":
            return .stairClimbing
        case "tennis":
            return .tennis
        case "badminton":
            return .badminton
        case "table_tennis":
            return .tableTennis
        case "soccer", "football":
            return .soccer
        case "basketball":
            return .basketball
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
        case .coreTraining: return "core_training"
        case .functionalStrengthTraining: return "functional_training"
        case .mixedCardio: return "mixed_cardio"
        case .stairClimbing: return "stair_climbing"
        case .tennis: return "tennis"
        case .badminton: return "badminton"
        case .tableTennis: return "table_tennis"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
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
