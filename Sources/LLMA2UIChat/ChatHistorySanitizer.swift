import Foundation
import LLMClient

/// `LLMA2UIChat` の append-only ポリシーに沿って、過去ターンの assistant 発話に含まれる
/// `<a2ui-json>...</a2ui-json>` ブロックを最小要約に置き換えるためのユーティリティ。
///
/// **目的**: LLM が履歴中の自分の過去出力を見て「同じ surfaceId をまた update すれば良い」と
/// 推論してしまう誤誘導を防ぐ。runtime 側で append-only を強制していても、プロンプト的に
/// 「過去 surface は不変」と一貫させるため履歴側も整える。
///
/// **挙動**:
/// - assistant role の `.text` content 内の `<a2ui-json>...</a2ui-json>` を 1 つの
///   placeholder 文字列に置換する
/// - user role や tool 関連 content は触らない
/// - 1 つの text content 内に複数ブロックがあればそれぞれを個別に置換
///
/// **placeholder 形式**: `[a2ui surface emitted in earlier turn]`
/// surfaceId を残すと LLM が再利用しがちなので、**id は意図的に落とす**。
internal enum ChatHistorySanitizer {

    /// 置換に使う placeholder。テストからも参照する。
    static let placeholder = "[a2ui surface emitted in earlier turn]"

    /// `<a2ui-json>...</a2ui-json>` ブロックを placeholder に置換する（複数行・複数ブロック対応）。
    static func sanitize(_ messages: [LLMMessage]) -> [LLMMessage] {
        messages.map(sanitize(_:))
    }

    /// 1 つの assistant message 内の text content を書き換える。
    static func sanitize(_ message: LLMMessage) -> LLMMessage {
        guard message.role == .assistant else { return message }
        let rewritten = message.contents.map { content -> LLMMessage.MessageContent in
            if case .text(let s) = content {
                return .text(stripA2UIBlocks(in: s))
            }
            return content
        }
        return LLMMessage(role: message.role, contents: rewritten)
    }

    // MARK: - Internal

    /// 文字列内の `<a2ui-json>...</a2ui-json>` ペアを placeholder に置換する。
    /// non-greedy で 1 ブロックずつ。タグ間に改行があってもマッチする。
    static func stripA2UIBlocks(in text: String) -> String {
        guard text.contains("<a2ui-json>") else { return text }
        let pattern = "<a2ui-json>[\\s\\S]*?</a2ui-json>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: placeholder)
        )
    }
}
