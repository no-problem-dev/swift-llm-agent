public struct A2UIAgentConfiguration: Sendable {
    public let maxParseRetries: Int

    public init(maxParseRetries: Int = 2) {
        self.maxParseRetries = maxParseRetries
    }

    public static let `default` = A2UIAgentConfiguration()
}
