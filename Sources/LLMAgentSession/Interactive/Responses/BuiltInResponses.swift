/// 却下レスポンス
public struct DismissedResponse: InteractionResponseProtocol {
    public var textValue: String { "Dismissed" }
    public init() {}
}

/// テキストレスポンス
public struct TextResponse: InteractionResponseProtocol {
    public let text: String
    public var textValue: String { text.isEmpty ? "No answer provided" : text }
    public init(text: String) { self.text = text }
}

/// 選択レスポンス
public struct SelectedResponse: InteractionResponseProtocol {
    public let ids: [String]
    public var textValue: String { ids.joined(separator: ", ") }
    public init(ids: [String]) { self.ids = ids }
}

/// 確認レスポンス
public struct ConfirmationResponse: InteractionResponseProtocol {
    public let decision: ConfirmationDecision

    public var textValue: String {
        switch decision {
        case .approved:
            return "Approved"
        case .modified(let text):
            return "Modified: \(text)"
        case .rejected:
            return "Rejected"
        }
    }

    public init(decision: ConfirmationDecision) { self.decision = decision }
}

/// アクションレスポンス
public struct ActionResponse: InteractionResponseProtocol {
    public let message: String
    public var textValue: String { message }
    public init(message: String) { self.message = message }
}
