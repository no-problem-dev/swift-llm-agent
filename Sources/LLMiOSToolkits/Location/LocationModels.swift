@preconcurrency import CoreLocation
import Foundation
@preconcurrency import MapKit

// MARK: - Input Types

struct GetCurrentLocationInput: Codable {}

struct SearchPlacesInput: Codable {
    var query: String
    var latitude: Double?
    var longitude: Double?
    var radius: Double?
    var limit: Int?
}

struct GetDirectionsInput: Codable {
    var originLatitude: Double?
    var originLongitude: Double?
    var originAddress: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationAddress: String?
    var transportType: String?

    enum CodingKeys: String, CodingKey {
        case originLatitude = "origin_latitude"
        case originLongitude = "origin_longitude"
        case originAddress = "origin_address"
        case destinationLatitude = "destination_latitude"
        case destinationLongitude = "destination_longitude"
        case destinationAddress = "destination_address"
        case transportType = "transport_type"
    }
}

struct GeocodeInput: Codable {
    var address: String?
    var latitude: Double?
    var longitude: Double?
}

// MARK: - Output Types

struct LocationInfo: Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var address: String?
    var city: String?
    var state: String?
    var country: String?
    var postalCode: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, address, city, state, country
        case postalCode = "postal_code"
    }
}

struct PlaceInfo: Codable, Sendable {
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var category: String?
    var phoneNumber: String?
    var url: String?
    var distance: Double?

    enum CodingKeys: String, CodingKey {
        case name, address, latitude, longitude, category
        case phoneNumber = "phone_number"
        case url, distance
    }
}

struct DirectionsInfo: Codable, Sendable {
    var distance: Double
    var distanceText: String
    var expectedTravelTime: Double
    var travelTimeText: String
    var transportType: String
    var steps: [RouteStepInfo]

    enum CodingKeys: String, CodingKey {
        case distance
        case distanceText = "distance_text"
        case expectedTravelTime = "expected_travel_time"
        case travelTimeText = "travel_time_text"
        case transportType = "transport_type"
        case steps
    }
}

struct RouteStepInfo: Codable, Sendable {
    var instructions: String
    var distance: Double
    var distanceText: String

    enum CodingKeys: String, CodingKey {
        case instructions, distance
        case distanceText = "distance_text"
    }
}

struct GeocodeResultInfo: Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var formattedAddress: String?
    var city: String?
    var state: String?
    var country: String?
    var postalCode: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case formattedAddress = "formatted_address"
        case city, state, country
        case postalCode = "postal_code"
    }
}

// MARK: - Errors

enum LocationError: Error, LocalizedError {
    case authorizationTimeout
    case locationTimeout
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationTimeout:
            "Location authorization request timed out. "
                + "Please respond to the location permission dialog."
        case .locationTimeout:
            "Location request timed out. "
                + "Ensure location services are enabled and you have a clear view of the sky."
        case .locationUnavailable:
            "Current location is not available."
        }
    }
}

// MARK: - Helpers

enum LocationHelper {
    static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)min"
        } else {
            return "\(minutes)min"
        }
    }

    static func transportType(from string: String?) -> MKDirectionsTransportType {
        switch string?.lowercased() {
        case "walking", "walk":
            return .walking
        case "transit", "train", "bus":
            return .transit
        case "driving", "car", "automobile":
            return .automobile
        default:
            return .automobile
        }
    }

    static func transportTypeName(_ type: MKDirectionsTransportType) -> String {
        switch type {
        case .walking:
            return "walking"
        case .transit:
            return "transit"
        case .automobile:
            return "driving"
        default:
            return "driving"
        }
    }

    static func geocodeResultInfo(from placemark: CLPlacemark) -> GeocodeResultInfo {
        GeocodeResultInfo(
            latitude: placemark.location?.coordinate.latitude ?? 0,
            longitude: placemark.location?.coordinate.longitude ?? 0,
            formattedAddress: [
                placemark.thoroughfare,
                placemark.subThoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.postalCode,
                placemark.country,
            ].compactMap { $0 }.joined(separator: ", "),
            city: placemark.locality,
            state: placemark.administrativeArea,
            country: placemark.country,
            postalCode: placemark.postalCode
        )
    }
}
