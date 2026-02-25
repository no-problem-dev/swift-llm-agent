import Foundation

// MARK: - Input Types

struct GetCurrentWeatherInput: Codable {
    var latitude: Double?
    var longitude: Double?
    var location: String?
}

struct GetForecastInput: Codable {
    var latitude: Double?
    var longitude: Double?
    var location: String?
    var days: Int?
}

// MARK: - Output Types

struct CurrentWeatherInfo: Codable, Sendable {
    var temperature: Double
    var feelsLike: Double
    var condition: String
    var humidity: Double
    var windSpeed: Double
    var windDirection: String?
    var uvIndex: Double?
    var visibility: Double?
    var pressure: Double?
    var locationName: String?

    enum CodingKeys: String, CodingKey {
        case temperature
        case feelsLike = "feels_like"
        case condition, humidity
        case windSpeed = "wind_speed"
        case windDirection = "wind_direction"
        case uvIndex = "uv_index"
        case visibility, pressure
        case locationName = "location_name"
    }
}

struct DailyForecastInfo: Codable, Sendable {
    var date: String
    var highTemperature: Double
    var lowTemperature: Double
    var condition: String
    var precipitationChance: Double
    var windSpeed: Double
    var uvIndex: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case highTemperature = "high_temperature"
        case lowTemperature = "low_temperature"
        case condition
        case precipitationChance = "precipitation_chance"
        case windSpeed = "wind_speed"
        case uvIndex = "uv_index"
    }
}

struct ForecastInfo: Codable, Sendable {
    var locationName: String?
    var dailyForecasts: [DailyForecastInfo]

    enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case dailyForecasts = "daily_forecasts"
    }
}
