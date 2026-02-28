import Foundation

// MARK: - InteractionRequest

/// インタラクション要求
///
/// エージェントが実行中（Layer 1: InteractiveTool）または
/// 完了後（Layer 2: DirectiveGenerator）に UI に対して発行するインタラクション要求。
/// UI はこの要求を受け取り、適切なインタラクション UI を表示する。
///
/// ## Layer 1: 実行中インタラクション
///
/// InteractiveTool の検出時に生成される。ユーザーの応答後、エージェントループが再開される。
///
/// ```swift
/// case .awaitingInteraction(let request):
///     // request.type に応じた UI を表示
///     InteractionView(request: request) { response in
///         await session.respond(response)
///     }
/// ```
///
/// ## Layer 2: 完了後ディレクティブ
///
/// DirectiveGenerator によりセッション完了後に生成される。
/// ユーザーの選択に応じて新しいターンを開始する。
public struct InteractionRequest: Sendable, Codable, Identifiable {
    /// 要求の一意識別子
    public let id: String

    /// インタラクションの種類
    public let type: InteractionType

    /// ユーザーに表示するプロンプト文
    public let prompt: String

    /// インタラクション固有のペイロード
    public let payload: InteractionPayload

    /// ユーザーがインタラクションを却下可能かどうか
    public let dismissible: Bool

    public init(
        id: String = UUID().uuidString,
        type: InteractionType,
        prompt: String,
        payload: InteractionPayload,
        dismissible: Bool = false
    ) {
        self.id = id
        self.type = type
        self.prompt = prompt
        self.payload = payload
        self.dismissible = dismissible
    }
}

// MARK: - Equatable

extension InteractionRequest: Equatable {
    public static func == (lhs: InteractionRequest, rhs: InteractionRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension InteractionRequest: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - InteractionType

/// インタラクションの種類
public enum InteractionType: String, Sendable, Codable, CaseIterable {
    /// 自由テキスト入力（現 ask_user の後継）
    case textInput

    /// 選択肢から選ぶ
    case selection

    /// 承認/修正/却下
    case confirmation

    /// アクションボタン + クイックリプライ
    case actionMenu
}

// MARK: - InteractionPayload

/// インタラクション固有のペイロード
public enum InteractionPayload: Sendable, Codable {
    /// テキスト入力用
    case textInput(placeholder: String?, multiline: Bool)

    /// 選択肢から選ぶ
    case selection(options: [SelectionOption], allowMultiple: Bool = false)

    /// 承認/修正/却下
    case confirmation(proposal: String, allowModification: Bool)

    /// アクションメニュー
    case actionMenu(actions: [ActionOption], quickReplies: [QuickReplyOption])
}
