/// 全インタラクションペイロードの基底プロトコル
///
/// インタラクションの種類はペイロードの型自体で決定される。
/// `InteractionType` enum は不要 — ペイロード型がそのまま種別を表す。
public protocol InteractionPayloadProtocol: Sendable {}
