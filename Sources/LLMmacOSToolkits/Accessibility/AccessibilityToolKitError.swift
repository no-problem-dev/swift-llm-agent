#if os(macOS)

import Foundation

/// AccessibilityToolKit のエラー
public enum AccessibilityToolKitError: Error, LocalizedError {
    case permissionRequired
    case appNotFound(name: String)
    case elementNotFound(criteria: String)
    case actionFailed(action: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return """
                Accessibility permission is required. \
                Grant access in System Settings > Privacy & Security > Accessibility.
                """
        case .appNotFound(let name):
            return "Application not found: \(name)"
        case .elementNotFound(let criteria):
            return "UI element not found matching: \(criteria)"
        case .actionFailed(let action, let message):
            return "Action '\(action)' failed: \(message)"
        }
    }
}

#endif
