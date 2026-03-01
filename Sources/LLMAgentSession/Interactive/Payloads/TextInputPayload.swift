/// テキスト入力ペイロード（ask_user 用）
public struct TextInputPayload: InteractionPayloadProtocol {
    public let placeholder: String?
    public let multiline: Bool

    public init(placeholder: String? = nil, multiline: Bool = false) {
        self.placeholder = placeholder
        self.multiline = multiline
    }
}
