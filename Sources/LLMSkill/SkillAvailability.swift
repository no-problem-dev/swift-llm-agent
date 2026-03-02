/// スキルの利用可能性
///
/// スキルが常時有効（required）か、ユーザーが任意に有効化（optional）かを定義する。
///
/// - `required`: 常時有効。ユーザーは無効化できない。
/// - `optional`: デフォルト無効。ユーザーが明示的に有効化する。
public enum SkillAvailability: String, Sendable, Codable, Equatable {
    /// 常時有効。ユーザーは無効化できない。
    case required
    /// デフォルト無効。ユーザーが明示的に有効化する。
    case optional
}
