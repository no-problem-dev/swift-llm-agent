import Foundation

// MARK: - InteractionRequest

/// インタラクション要求
///
/// エージェントが実行中（Layer 1: InteractiveTool）または
/// 完了後（Layer 2: DirectiveGenerator）に UI に対して発行するインタラクション要求。
/// UI はこの要求を受け取り、適切なインタラクション UI を表示する。
///
/// ## 設計
///
/// インタラクションの種類はペイロードの型で決定される。
/// `InteractionType` enum は不要 — `payload.rawValue` の具体型がそのまま種別を表す。
///
/// ## Layer 1: 実行中インタラクション
///
/// InteractiveTool の検出時に生成される。ユーザーの応答後、エージェントループが再開される。
///
/// ```swift
/// case .awaitingInteraction(let request):
///     // payload の型に応じた View が自動的に選択される
///     InteractionView(request: request) { response in
///         await session.respond(response)
///     }
/// ```
///
/// ## Layer 2: 完了後ディレクティブ
///
/// DirectiveGenerator によりセッション完了後に生成される。
/// ユーザーの選択に応じて新しいターンを開始する。
public struct InteractionRequest: Sendable, Identifiable {
    /// 要求の一意識別子
    public let id: String

    /// ユーザーに表示するプロンプト文
    public let prompt: String

    /// インタラクション固有のペイロード（existential 容器）
    public let payload: InteractionPayload

    /// ユーザーがインタラクションを却下可能かどうか
    public let dismissible: Bool

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        payload: InteractionPayload,
        dismissible: Bool = false
    ) {
        self.id = id
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

// MARK: - InteractionPayload

/// 型消去されたペイロード容器
///
/// プロトコル準拠型を保持し、`as?` で具体型を復元する。
/// View 層では `rawValue as? ViewableInteractionPayload` で
/// retroactive conformance を検出し、ペイロードが自身の View を返す。
public struct InteractionPayload: @unchecked Sendable {
    /// 内部の existential（View 層での `as?` キャスト用に公開）
    public let rawValue: any InteractionPayloadProtocol

    public init(_ value: some InteractionPayloadProtocol) {
        self.rawValue = value
    }

    /// 型安全にペイロードを取得
    public func value<T: InteractionPayloadProtocol>(as type: T.Type) -> T? {
        rawValue as? T
    }
}
