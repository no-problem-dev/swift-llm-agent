import A2UICore
import A2UIParser

public enum A2UIDecodeEvent: Sendable {
    case attempt(index: Int, text: String)
    case succeeded(attemptIndex: Int, parts: [A2UIResponsePart])
    case failed(attemptIndex: Int, text: String, errors: [A2UIParseError])
    case retryRequested(nextAttemptIndex: Int, reasons: [String])
    case retriesExhausted(attempts: Int, lastErrors: [A2UIParseError])
}

public struct A2UIParseError: Sendable, Equatable {
    public let blockIndex: Int
    public let rawJSON: String
    public let message: String

    public init(blockIndex: Int, rawJSON: String, message: String) {
        self.blockIndex = blockIndex
        self.rawJSON = rawJSON
        self.message = message
    }
}
