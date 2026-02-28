#if os(macOS)

import AppKit
import Foundation

// MARK: - Input Models

struct AppNameInput: Codable {
    var name: String
}

struct AppLaunchInput: Codable {
    var name: String
    var hidden: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case hidden
    }
}

struct AppQuitInput: Codable {
    var name: String
    var force: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case force
    }
}

// MARK: - Output Models

struct RunningAppInfo: Codable, Sendable {
    var localizedName: String?
    var bundleIdentifier: String?
    var processIdentifier: Int32
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case localizedName = "localized_name"
        case bundleIdentifier = "bundle_identifier"
        case processIdentifier = "process_identifier"
        case isActive = "is_active"
    }

    init(from app: NSRunningApplication) {
        self.localizedName = app.localizedName
        self.bundleIdentifier = app.bundleIdentifier
        self.processIdentifier = app.processIdentifier
        self.isActive = app.isActive
    }
}

#endif
