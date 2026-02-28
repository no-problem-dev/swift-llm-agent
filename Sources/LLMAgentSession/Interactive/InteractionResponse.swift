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

/// インタラクション応答の内容
public enum InteractionResponseContent: Sendable {
    /// 自由テキスト
    case text(String)

    /// 選択された項目の ID リスト
    case selected([String])

    /// 承認判断
    case confirmation(ConfirmationDecision)

    /// アクション実行（アクションのメッセージ）
    case action(String)

    /// インタラクションを却下
    case dismissed
}

// MARK: - Convenience

extension InteractionResponseContent {
    /// ツール結果として使用する文字列値を取得
    public var textValue: String {
        switch self {
        case .text(let text):
            return text.isEmpty ? "No answer provided" : text
        case .selected(let ids):
            return ids.joined(separator: ", ")
        case .confirmation(let decision):
            switch decision {
            case .approved:
                return "Approved"
            case .modified(let text):
                return "Modified: \(text)"
            case .rejected:
                return "Rejected"
            }
        case .action(let message):
            return message
        case .dismissed:
            return "Dismissed"
        }
    }
}
