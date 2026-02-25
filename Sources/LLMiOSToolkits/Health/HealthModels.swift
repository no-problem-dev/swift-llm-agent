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

    enum CodingKeys: String, CodingKey {
        case period
        case startDate = "start_date"
        case endDate = "end_date"
        case steps, distance
        case activeEnergy = "active_energy"
        case heartRateAvg = "heart_rate_avg"
        case sleepHours = "sleep_hours"
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
