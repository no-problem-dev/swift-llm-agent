#if os(macOS)

import Foundation

// MARK: - Output Models

/// ウィンドウ情報
struct WindowInfo: Codable, Sendable {
    var ownerName: String
    var title: String?
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var isOnScreen: Bool
    var isFocused: Bool

    enum CodingKeys: String, CodingKey {
        case ownerName = "owner_name"
        case title
        case x, y, width, height
        case isOnScreen = "is_on_screen"
        case isFocused = "is_focused"
    }
}

// MARK: - Input Models

struct WindowAppInput: Codable {
    var appName: String

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
    }
}

struct WindowFocusInput: Codable {
    var appName: String
    var windowTitle: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case windowTitle = "window_title"
    }
}

struct WindowResizeInput: Codable {
    var appName: String
    var windowTitle: String?
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case windowTitle = "window_title"
        case x, y, width, height
    }
}

struct WindowMinimizeInput: Codable {
    var appName: String
    var windowTitle: String?
    var restore: Bool?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case windowTitle = "window_title"
        case restore
    }
}

#endif
