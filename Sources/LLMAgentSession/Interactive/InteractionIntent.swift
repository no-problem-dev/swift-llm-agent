import Foundation

// MARK: - InteractionIntent

/// インタラクション要求（UIAgent のインタラクションをラップ）
public struct InteractionIntent: Sendable, Identifiable {
    public let id: String
    public let toolCallId: String
    public let toolName: String
    public let request: InteractionRequest

    public init(
        id: String = UUID().uuidString,
        toolCallId: String,
        toolName: String,
        request: InteractionRequest
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.request = request
    }
}
