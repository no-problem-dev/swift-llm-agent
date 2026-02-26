@preconcurrency import CoreLocation
import Foundation
import LLMClient
import LLMTool
@preconcurrency import MapKit
import LLMMCP

// MARK: - LocationToolKit

/// 位置情報・地図・ルート検索を提供する ToolKit
///
/// CoreLocation と MapKit を使用して、現在地取得、周辺検索、
/// ルート検索、ジオコーディングを提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     LocationToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_current_location`: 現在地の取得（緯度経度 + 住所）
/// - `search_places`: 周辺の場所を検索（カテゴリ・キーワード）
/// - `get_directions`: 2地点間のルート検索（徒歩/車/電車）
/// - `geocode`: 住所 ↔ 座標の変換
public final class LocationToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "location"

    private let locationManager: CLLocationManager
    private let delegate: LocationManagerDelegate
    private let guard_: PermissionGuard
    private let geocoder: CLGeocoder

    // MARK: - Initialization

    /// LocationToolKit を作成
    public init() {
        self.locationManager = CLLocationManager()
        self.delegate = LocationManagerDelegate()
        self.locationManager.delegate = delegate
        self.guard_ = PermissionGuard(
            provider: LocationPermission(
                locationManager: locationManager,
                delegate: delegate
            )
        )
        self.geocoder = CLGeocoder()
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            getCurrentLocationTool,
            searchPlacesTool,
            getDirectionsTool,
            geocodeTool,
        ]
    }

    // MARK: - get_current_location

    private var getCurrentLocationTool: BuiltInTool {
        BuiltInTool(
            name: "get_current_location",
            description: "Get the user's current location with coordinates and address. "
                + "Requires location permission.",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Current Location",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [guard_, locationManager, delegate, geocoder] data in
            if let error = await guard_.ensureAuthorized() { return error }

            // AsyncStream で能動的に位置を取得（キャッシュ依存を排除）
            let stream = delegate.locationStream()

            await MainActor.run {
                locationManager.requestLocation()
            }

            let location: CLLocation
            do {
                location = try await withThrowingTaskGroup(of: CLLocation.self) { group in
                    group.addTask {
                        for await result in stream {
                            switch result {
                            case .success(let loc):
                                return loc
                            case .failure(let error):
                                throw error
                            }
                        }
                        throw LocationError.locationUnavailable
                    }

                    group.addTask {
                        try await Task.sleep(for: .seconds(15))
                        throw LocationError.locationTimeout
                    }

                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            } catch {
                return .error(
                    "Failed to get current location: \(error.localizedDescription)"
                )
            }

            let coordinate = location.coordinate

            // 逆ジオコーディングで住所を取得
            var locationInfo = LocationInfo(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    locationInfo.address = [
                        placemark.thoroughfare,
                        placemark.subThoroughfare,
                    ].compactMap { $0 }.joined(separator: " ")
                    locationInfo.city = placemark.locality
                    locationInfo.state = placemark.administrativeArea
                    locationInfo.country = placemark.country
                    locationInfo.postalCode = placemark.postalCode
                }
            } catch {
                // ジオコーディング失敗でも座標は返す
            }

            return try .encoded(locationInfo)
        }
    }

    // MARK: - search_places

    private var searchPlacesTool: BuiltInTool {
        BuiltInTool(
            name: "search_places",
            description: "Search for nearby places by keyword or category. "
                + "Can search around a specific location or the user's current location. "
                + "Returns place name, address, distance, and other details.",
            inputSchema: .object(
                properties: [
                    "query": .string(
                        description: "Search keyword or category (e.g., 'coffee', 'restaurant', 'pharmacy', 'ATM')"
                    ),
                    "latitude": .number(
                        description: "Center latitude for search. Uses current location if omitted."
                    ),
                    "longitude": .number(
                        description: "Center longitude for search. Uses current location if omitted."
                    ),
                    "radius": .number(
                        description: "Search radius in meters (default: 1000, max: 50000)"
                    ),
                    "limit": .integer(
                        description: "Maximum number of results (default: 10, max: 50)"
                    ),
                ],
                required: ["query"]
            ),
            annotations: ToolAnnotations(
                title: "Search Places",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [guard_, locationManager] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SearchPlacesInput.self, from: data)
            let limit = min(input.limit ?? 10, 50)
            let radius = min(input.radius ?? 1000, 50000)

            let centerCoordinate: CLLocationCoordinate2D
            if let lat = input.latitude, let lon = input.longitude {
                centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let location = locationManager.location {
                centerCoordinate = location.coordinate
            } else {
                return .error(
                    "No location specified and current location is not available. "
                    + "Provide latitude/longitude or enable location services."
                )
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = input.query
            request.region = MKCoordinateRegion(
                center: centerCoordinate,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )

            do {
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                let centerLocation = CLLocation(
                    latitude: centerCoordinate.latitude,
                    longitude: centerCoordinate.longitude
                )

                let places: [PlaceInfo] = Array(response.mapItems.prefix(limit)).map { item in
                    let itemLocation = CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                    let distance = centerLocation.distance(from: itemLocation)

                    return PlaceInfo(
                        name: item.name ?? "Unknown",
                        address: item.placemark.formattedAddress,
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude,
                        category: item.pointOfInterestCategory?.rawValue,
                        phoneNumber: item.phoneNumber,
                        url: item.url?.absoluteString,
                        distance: (distance * 10).rounded() / 10
                    )
                }

                return try .encoded(places)
            } catch {
                return .error("Failed to search places: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - get_directions

    private var getDirectionsTool: BuiltInTool {
        BuiltInTool(
            name: "get_directions",
            description: "Get directions between two points. "
                + "Specify origin and destination by coordinates or address. "
                + "If origin is omitted, uses the user's current location.",
            inputSchema: .object(
                properties: [
                    "origin_latitude": .number(description: "Origin latitude"),
                    "origin_longitude": .number(description: "Origin longitude"),
                    "origin_address": .string(
                        description: "Origin address (alternative to coordinates). Uses current location if neither specified."
                    ),
                    "destination_latitude": .number(description: "Destination latitude"),
                    "destination_longitude": .number(description: "Destination longitude"),
                    "destination_address": .string(
                        description: "Destination address (alternative to coordinates)"
                    ),
                    "transport_type": .string(
                        description: "Transport type: 'driving' (default), 'walking', or 'transit'"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Directions",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [guard_, locationManager, geocoder] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(GetDirectionsInput.self, from: data)

            // Origin の解決
            let originItem: MKMapItem
            if let lat = input.originLatitude, let lon = input.originLongitude {
                let placemark = MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                originItem = MKMapItem(placemark: placemark)
            } else if let address = input.originAddress {
                guard let resolved = try await Self.geocodeAddress(address, geocoder: geocoder) else {
                    return .error("Could not geocode origin address: \(address)")
                }
                originItem = resolved
            } else if let location = locationManager.location {
                originItem = MKMapItem(
                    placemark: MKPlacemark(coordinate: location.coordinate)
                )
            } else {
                return .error(
                    "Origin not specified and current location is not available. "
                    + "Provide origin coordinates or address."
                )
            }

            // Destination の解決
            let destItem: MKMapItem
            if let lat = input.destinationLatitude, let lon = input.destinationLongitude {
                let placemark = MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                destItem = MKMapItem(placemark: placemark)
            } else if let address = input.destinationAddress {
                guard let resolved = try await Self.geocodeAddress(address, geocoder: geocoder) else {
                    return .error("Could not geocode destination address: \(address)")
                }
                destItem = resolved
            } else {
                return .error(
                    "Destination is required. Provide destination coordinates or address."
                )
            }

            let transportType = LocationHelper.transportType(from: input.transportType)

            let request = MKDirections.Request()
            request.source = originItem
            request.destination = destItem
            request.transportType = transportType

            do {
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()

                guard let route = response.routes.first else {
                    return .error("No route found between the specified locations.")
                }

                let info = DirectionsInfo(
                    distance: route.distance,
                    distanceText: LocationHelper.formatDistance(route.distance),
                    expectedTravelTime: route.expectedTravelTime,
                    travelTimeText: LocationHelper.formatDuration(route.expectedTravelTime),
                    transportType: LocationHelper.transportTypeName(transportType),
                    steps: route.steps.compactMap { step in
                        guard !step.instructions.isEmpty else { return nil }
                        return RouteStepInfo(
                            instructions: step.instructions,
                            distance: step.distance,
                            distanceText: LocationHelper.formatDistance(step.distance)
                        )
                    }
                )

                return try .encoded(info)
            } catch {
                return .error("Failed to get directions: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - geocode

    private var geocodeTool: BuiltInTool {
        BuiltInTool(
            name: "geocode",
            description: "Convert between addresses and coordinates. "
                + "Provide 'address' to get coordinates (forward geocoding), "
                + "or 'latitude' and 'longitude' to get the address (reverse geocoding).",
            inputSchema: .object(
                properties: [
                    "address": .string(
                        description: "Address to geocode (forward geocoding)"
                    ),
                    "latitude": .number(
                        description: "Latitude for reverse geocoding"
                    ),
                    "longitude": .number(
                        description: "Longitude for reverse geocoding"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Geocode",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { [geocoder] data in
            let input = try JSONDecoder().decode(GeocodeInput.self, from: data)

            if let address = input.address, !address.isEmpty {
                // Forward geocoding: address → coordinates
                do {
                    let placemarks = try await geocoder.geocodeAddressString(address)
                    let results = placemarks.map { LocationHelper.geocodeResultInfo(from: $0) }
                    return try .encoded(results)
                } catch {
                    return .error("Failed to geocode address: \(error.localizedDescription)")
                }
            } else if let lat = input.latitude, let lon = input.longitude {
                // Reverse geocoding: coordinates → address
                let location = CLLocation(latitude: lat, longitude: lon)
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    let results = placemarks.map { LocationHelper.geocodeResultInfo(from: $0) }
                    return try .encoded(results)
                } catch {
                    return .error("Failed to reverse geocode: \(error.localizedDescription)")
                }
            } else {
                return .error(
                    "Provide either 'address' for forward geocoding, "
                    + "or 'latitude' and 'longitude' for reverse geocoding."
                )
            }
        }
    }

    // MARK: - Helpers

    private static func geocodeAddress(
        _ address: String,
        geocoder: CLGeocoder
    ) async throws -> MKMapItem? {
        let placemarks = try await geocoder.geocodeAddressString(address)
        guard let placemark = placemarks.first, let location = placemark.location else {
            return nil
        }
        let mkPlacemark = MKPlacemark(
            coordinate: location.coordinate
        )
        return MKMapItem(placemark: mkPlacemark)
    }
}

// MARK: - MKPlacemark Extension

extension MKPlacemark {
    var formattedAddress: String? {
        let components = [
            thoroughfare,
            subThoroughfare,
            locality,
            administrativeArea,
            postalCode,
            country,
        ].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}
