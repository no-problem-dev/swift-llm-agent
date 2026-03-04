import Foundation

// MARK: - InteractionRequest

/// インタラクション要求
///
/// エージェントの InteractiveTool がユーザー入力を要求する際に生成される。
/// UIAgent 経由で UI に配信され、ユーザーの応答後にチャネル経由でループが再開される。
///
/// ## 設計
///
/// インタラクションの種類はペイロードの型で決定される。
/// `InteractionType` enum は不要 — `payload.rawValue` の具体型がそのまま種別を表す。
///
/// ```swift
/// // UIAgentEvent.interactionRequested で受け取り
/// InteractionView(request: intent.request) { response in
///     await channel.postResponse(.interactionResponse(response, forRequestId: intent.id), from: "user")
/// }
/// ```
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
