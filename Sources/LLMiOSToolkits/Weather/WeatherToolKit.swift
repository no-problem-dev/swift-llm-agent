@preconcurrency import CoreLocation
import Foundation
import LLMClient
import LLMTool
import LLMMCP
import WeatherKit

// MARK: - WeatherToolKit

/// 天気情報を提供する ToolKit
///
/// WeatherKit を使用して、現在の天気と天気予報を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     WeatherToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_current_weather`: 指定地点の現在の天気を取得
/// - `get_forecast`: 指定地点の天気予報を取得（日別）
///
/// ## 注意事項
///
/// WeatherKit entitlement と Apple Developer Program が必要です。
public final class WeatherToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "weather"

    private let weatherService: WeatherService
    private let geocoder: CLGeocoder

    // MARK: - Initialization

    public init() {
        self.weatherService = WeatherService.shared
        self.geocoder = CLGeocoder()
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            getCurrentWeatherTool,
            getForecastTool,
        ]
    }

    // MARK: - get_current_weather

    private var getCurrentWeatherTool: BuiltInTool {
        BuiltInTool(
            name: "get_current_weather",
            description: "Get the current weather conditions for a location. "
                + "Specify by coordinates (latitude/longitude) or by location name.",
            inputSchema: .object(
                properties: [
                    "latitude": .number(description: "Latitude of the location"),
                    "longitude": .number(description: "Longitude of the location"),
                    "location": .string(
                        description: "Location name (e.g., 'Tokyo', 'New York'). "
                            + "Used if latitude/longitude are not specified."
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Current Weather",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [weatherService, geocoder] data in
            let input = try JSONDecoder().decode(GetCurrentWeatherInput.self, from: data)

            guard let location = try await Self.resolveLocation(
                latitude: input.latitude,
                longitude: input.longitude,
                locationName: input.location,
                geocoder: geocoder
            ) else {
                return .error(
                    "Location is required. Provide latitude/longitude or a location name."
                )
            }

            do {
                let weather = try await weatherService.weather(for: location)
                let current = weather.currentWeather

                var locationName: String?
                if let name = input.location {
                    locationName = name
                } else {
                    let placemarks = try? await geocoder.reverseGeocodeLocation(location)
                    locationName = placemarks?.first?.locality
                }

                let info = CurrentWeatherInfo(
                    temperature: current.temperature.value,
                    feelsLike: current.apparentTemperature.value,
                    condition: current.condition.description,
                    humidity: current.humidity * 100,
                    windSpeed: current.wind.speed.value,
                    windDirection: current.wind.compassDirection.description,
                    uvIndex: Double(current.uvIndex.value),
                    visibility: current.visibility.value,
                    pressure: current.pressure.value,
                    locationName: locationName
                )
                return try .encoded(info)
            } catch {
                return .error("Failed to get weather: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - get_forecast

    private var getForecastTool: BuiltInTool {
        BuiltInTool(
            name: "get_forecast",
            description: "Get the weather forecast for a location. "
                + "Returns daily forecasts with high/low temperatures, conditions, and precipitation chance.",
            inputSchema: .object(
                properties: [
                    "latitude": .number(description: "Latitude of the location"),
                    "longitude": .number(description: "Longitude of the location"),
                    "location": .string(
                        description: "Location name (e.g., 'Tokyo', 'Osaka'). "
                            + "Used if latitude/longitude are not specified."
                    ),
                    "days": .integer(
                        description: "Number of forecast days (default: 7, max: 10)"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Forecast",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [weatherService, geocoder] data in
            let input = try JSONDecoder().decode(GetForecastInput.self, from: data)
            let days = min(input.days ?? 7, 10)

            guard let location = try await Self.resolveLocation(
                latitude: input.latitude,
                longitude: input.longitude,
                locationName: input.location,
                geocoder: geocoder
            ) else {
                return .error(
                    "Location is required. Provide latitude/longitude or a location name."
                )
            }

            do {
                let weather = try await weatherService.weather(for: location)
                let forecasts = Array(weather.dailyForecast.prefix(days))

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                var locationName: String?
                if let name = input.location {
                    locationName = name
                } else {
                    let placemarks = try? await geocoder.reverseGeocodeLocation(location)
                    locationName = placemarks?.first?.locality
                }

                let dailyForecasts = forecasts.map { day in
                    DailyForecastInfo(
                        date: dateFormatter.string(from: day.date),
                        highTemperature: day.highTemperature.value,
                        lowTemperature: day.lowTemperature.value,
                        condition: day.condition.description,
                        precipitationChance: day.precipitationChance * 100,
                        windSpeed: day.wind.speed.value,
                        uvIndex: Double(day.uvIndex.value)
                    )
                }

                let info = ForecastInfo(
                    locationName: locationName,
                    dailyForecasts: dailyForecasts
                )
                return try .encoded(info)
            } catch {
                return .error("Failed to get forecast: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func resolveLocation(
        latitude: Double?,
        longitude: Double?,
        locationName: String?,
        geocoder: CLGeocoder
    ) async throws -> CLLocation? {
        if let lat = latitude, let lon = longitude {
            return CLLocation(latitude: lat, longitude: lon)
        }
        if let name = locationName, !name.isEmpty {
            let placemarks = try await geocoder.geocodeAddressString(name)
            if let location = placemarks.first?.location {
                return location
            }
        }
        return nil
    }
}
