import Foundation

/// アイテム（Skill / SubAgent）のスコープ
///
/// カスタム Skill / SubAgent がどのレベルで定義されているかを示します。
/// 同名アイテムの優先度解決に使用: `project` > `global` > `catalog`
public enum ItemScope: String, Sendable, Codable, CaseIterable {
    /// アプリ提供のカタログアイテム（プロジェクトにインストールして使用）
    case catalog

    /// デフォルトプロジェクト配下のグローバルアイテム（全プロジェクトで有効）
    case global

    /// 特定プロジェクト配下のアイテム（そのプロジェクト選択時のみ有効）
    case project
}
