/// 選択肢ペイロード（ask_selection 用）
public struct SelectionPayload: InteractionPayloadProtocol {
    public let options: [SelectionOption]
    public let allowMultiple: Bool

    public init(options: [SelectionOption], allowMultiple: Bool = false) {
        self.options = options
        self.allowMultiple = allowMultiple
    }
}
