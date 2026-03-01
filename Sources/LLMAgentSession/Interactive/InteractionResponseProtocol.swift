import LLMClient

/// 全インタラクション応答の基底プロトコル
///
/// 各応答型は `textValue` で LLM に返すテキスト表現を提供する。
/// メディアデータを含む応答は `mediaContents` をオーバーライドして画像等を返す。
public protocol InteractionResponseProtocol: Sendable {
    /// LLM に返すテキスト表現
    var textValue: String { get }

    /// LLM に送信するメディアコンテンツ（画像等）
    var mediaContents: [ImageContent] { get }
}

extension InteractionResponseProtocol {
    public var mediaContents: [ImageContent] { [] }
}
