/// 確認ペイロード（ask_confirmation 用）
public struct ConfirmationPayload: InteractionPayloadProtocol {
    public let proposal: String
    public let allowModification: Bool

    public init(proposal: String, allowModification: Bool = true) {
        self.proposal = proposal
        self.allowModification = allowModification
    }
}
