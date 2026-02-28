#if os(macOS)

import Foundation

/// ShellToolKitのエラー
public enum ShellToolKitError: Error, LocalizedError {
    case timeout(seconds: TimeInterval)
    case executionFailed(message: String)
    case commandNotFound(command: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Shell command timed out after \(Int(seconds)) seconds"
        case .executionFailed(let message):
            return "Shell execution failed: \(message)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        }
    }
}

#endif
