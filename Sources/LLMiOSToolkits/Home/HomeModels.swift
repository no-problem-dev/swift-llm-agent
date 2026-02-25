import Foundation

// MARK: - Input Types

struct ListDevicesInput: Codable {
    var room: String?
}

struct GetDeviceStatusInput: Codable {
    var name: String?
    var id: String?
}

struct ControlDeviceInput: Codable {
    var name: String?
    var id: String?
    var action: String
    var value: String?
}

struct ActivateSceneInput: Codable {
    var name: String
}

// MARK: - Output Types

struct HomeDeviceInfo: Codable, Sendable {
    var id: String
    var name: String
    var room: String?
    var category: String
    var isReachable: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, room, category
        case isReachable = "is_reachable"
    }
}

struct DeviceStatusInfo: Codable, Sendable {
    var id: String
    var name: String
    var room: String?
    var category: String
    var isReachable: Bool
    var characteristics: [CharacteristicInfo]

    enum CodingKeys: String, CodingKey {
        case id, name, room, category
        case isReachable = "is_reachable"
        case characteristics
    }
}

struct CharacteristicInfo: Codable, Sendable {
    var type: String
    var value: String?
    var isReadable: Bool
    var isWritable: Bool

    enum CodingKeys: String, CodingKey {
        case type, value
        case isReadable = "is_readable"
        case isWritable = "is_writable"
    }
}

struct HomeSceneInfo: Codable, Sendable {
    var id: String
    var name: String
}
