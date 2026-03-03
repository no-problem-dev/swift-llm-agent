import Foundation

/// アイテム（Skill / SubAgent）のスコープ
///
/// カスタム Skill / SubAgent がどのレベルで定義されているかを示します。
/// 同名アイテムの優先度解決に使用: `project` > `global` > `builtIn`
public enum ItemScope: String, Sendable, Codable, CaseIterable {
    /// フレームワーク・アプリにバンドルされた組み込みアイテム
    case builtIn

    /// デフォルトプロジェクト配下のグローバルアイテム（全プロジェクトで有効）
    case global

    /// 特定プロジェクト配下のアイテム（そのプロジェクト選択時のみ有効）
    case project
}
