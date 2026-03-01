/// 全インタラクション応答の基底プロトコル
///
/// 各応答型は `textValue` で LLM に返すテキスト表現を提供する。
public protocol InteractionResponseProtocol: Sendable {
    /// LLM に返すテキスト表現
    var textValue: String { get }
}
