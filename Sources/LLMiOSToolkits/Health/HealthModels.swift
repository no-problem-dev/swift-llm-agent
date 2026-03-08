import Foundation

// MARK: - Input Types

struct QueryHealthDataInput: Codable {
    var dataType: String
    var startDate: String
    var endDate: String
    var aggregation: String?

    enum CodingKeys: String, CodingKey {
        case dataType = "data_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case aggregation
    }
}

struct GetHealthSummaryInput: Codable {
    var period: String?
}

struct QueryWorkoutsInput: Codable {
    var startDate: String?
    var endDate: String?
    var workoutType: String?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case workoutType = "workout_type"
        case limit
    }
}

struct SaveHealthDataInput: Codable {
    var dataType: String
    var value: Double
    var unit: String?
    var date: String?

    enum CodingKeys: String, CodingKey {
        case dataType = "data_type"
        case value, unit, date
    }
}

struct QuerySleepInput: Codable {
    var startDate: String
    var endDate: String

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct QueryMindfulnessInput: Codable {
    var startDate: String
    var endDate: String
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case limit
    }
}

// MARK: - Output Types

struct HealthDataResult: Codable, Sendable {
    var dataType: String
    var startDate: String
    var endDate: String
    var aggregation: String
    var value: Double?
    var unit: String?

    enum CodingKeys: String, CodingKey {
        case dataType = "data_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case aggregation, value, unit
    }
}

struct HealthSummary: Codable, Sendable {
    var period: String
    var startDate: String
    var endDate: String
    var steps: Double?
    var distance: Double?
    var activeEnergy: Double?
    var heartRateAvg: Double?
    var sleepHours: Double?
    var sleepDetails: SleepSummary?

    enum CodingKeys: String, CodingKey {
        case period
        case startDate = "start_date"
        case endDate = "end_date"
        case steps, distance
        case activeEnergy = "active_energy"
        case heartRateAvg = "heart_rate_avg"
        case sleepHours = "sleep_hours"
        case sleepDetails = "sleep_details"
    }
}

struct WorkoutInfo: Codable, Sendable {
    var workoutType: String
    var startDate: String
    var endDate: String
    var duration: Double
    var durationText: String
    var totalDistance: Double?
    var totalEnergyBurned: Double?

    enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case duration
        case durationText = "duration_text"
        case totalDistance = "total_distance"
        case totalEnergyBurned = "total_energy_burned"
    }
}

struct SaveHealthDataResult: Codable, Sendable {
    var dataType: String
    var value: Double
    var unit: String
    var date: String

    enum CodingKeys: String, CodingKey {
        case dataType = "data_type"
        case value, unit, date
    }
}

// MARK: - Sleep Analysis Types

struct SleepAnalysisResult: Codable, Sendable {
    var startDate: String
    var endDate: String
    var summary: SleepSummary
    var sessions: [SleepSession]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case summary, sessions
    }
}

struct SleepSummary: Codable, Sendable {
    var totalSleepMinutes: Double
    var inBedMinutes: Double
    var coreSleepMinutes: Double?
    var deepSleepMinutes: Double?
    var remSleepMinutes: Double?
    var awakeMinutes: Double?
    var sleepEfficiency: Double?

    enum CodingKeys: String, CodingKey {
        case totalSleepMinutes = "total_sleep_minutes"
        case inBedMinutes = "in_bed_minutes"
        case coreSleepMinutes = "core_sleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepEfficiency = "sleep_efficiency"
    }
}

struct SleepSession: Codable, Sendable {
    var stage: String
    var startDate: String
    var endDate: String
    var durationMinutes: Double

    enum CodingKeys: String, CodingKey {
        case stage
        case startDate = "start_date"
        case endDate = "end_date"
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Mindfulness Types

struct MindfulnessResult: Codable, Sendable {
    var startDate: String
    var endDate: String
    var totalMinutes: Double
    var sessionCount: Int
    var sessions: [MindfulnessSession]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case totalMinutes = "total_minutes"
        case sessionCount = "session_count"
        case sessions
    }
}

struct MindfulnessSession: Codable, Sendable {
    var startDate: String
    var endDate: String
    var durationMinutes: Double

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case durationMinutes = "duration_minutes"
    }
}
