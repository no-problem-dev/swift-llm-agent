/// アクションメニューペイロード（Layer 2 ディレクティブ用）
public struct ActionMenuPayload: InteractionPayloadProtocol {
    public let actions: [ActionOption]
    public let quickReplies: [QuickReplyOption]

    public init(actions: [ActionOption], quickReplies: [QuickReplyOption]) {
        self.actions = actions
        self.quickReplies = quickReplies
    }
}
