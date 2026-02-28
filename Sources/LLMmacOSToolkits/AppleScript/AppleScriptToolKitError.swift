#if os(macOS)

import Foundation

/// AppleScriptToolKit のエラー
public enum AppleScriptToolKitError: Error, LocalizedError {
    case timeout(seconds: Int)
    case compilationFailed(message: String)
    case executionFailed(message: String)
    case permissionDenied(target: String?)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Script timed out after \(seconds) seconds"
        case .compilationFailed(let message):
            return "Script compilation failed: \(message)"
        case .executionFailed(let message):
            return "Script execution failed: \(message)"
        case .permissionDenied(let target):
            let base = "Apple Events permission denied"
            let targetInfo = target.map { " for \($0)" } ?? ""
            return "\(base)\(targetInfo). Grant access in System Settings > Privacy & Security > Automation."
        }
    }
}

#endif
