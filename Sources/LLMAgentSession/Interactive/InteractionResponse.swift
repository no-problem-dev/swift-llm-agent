import Foundation

// MARK: - InteractionResponse

/// インタラクション応答
///
/// UI がユーザーの操作を受けて `InteractionRequest` に対して返す応答。
/// セッションはこの応答を受け取り、エージェントループを再開する（Layer 1）
/// または新しいターンを開始する（Layer 2）。
public struct InteractionResponse: Sendable {
    /// 対応する InteractionRequest の ID
    public let requestId: String

    /// 応答内容
    public let content: InteractionResponseContent

    public init(requestId: String, content: InteractionResponseContent) {
        self.requestId = requestId
        self.content = content
    }
}

// MARK: - InteractionResponseContent

/// 型消去されたレスポンス容器
///
/// `InteractionResponseProtocol` 準拠型を保持し、`as?` で具体型を復元する。
public struct InteractionResponseContent: @unchecked Sendable {
    private let storage: any InteractionResponseProtocol

    public init(_ value: some InteractionResponseProtocol) {
        self.storage = value
    }

    /// ツール結果として使用する文字列値を取得
    public var textValue: String { storage.textValue }

    /// 却下されたかどうか
    public var isDismissed: Bool { storage is DismissedResponse }

    /// 型安全にレスポンスを取得
    public func value<T: InteractionResponseProtocol>(as type: T.Type) -> T? {
        storage as? T
    }

    // MARK: - Factory Methods

    /// 却下レスポンス
    public static let dismissed = InteractionResponseContent(DismissedResponse())

    /// テキストレスポンス
    public static func text(_ text: String) -> Self { .init(TextResponse(text: text)) }

    /// 選択レスポンス
    public static func selected(_ ids: [String]) -> Self { .init(SelectedResponse(ids: ids)) }

    /// 確認レスポンス
    public static func confirmation(_ decision: ConfirmationDecision) -> Self {
        .init(ConfirmationResponse(decision: decision))
    }

    /// アクションレスポンス
    public static func action(_ message: String) -> Self { .init(ActionResponse(message: message)) }
}
