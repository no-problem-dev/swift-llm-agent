import Foundation

// MARK: - SkillKit

/// 関連するスキルをグループ化するプロトコル
///
/// ToolKit のスキル版。複数の関連スキルを束ねて提供します。
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     BuiltInSkillKit()
///     CustomSkillKit()
/// }
/// ```
///
/// ## 実装例
///
/// ```swift
/// public struct MySkillKit: SkillKit {
///     public var name: String { "my-skills" }
///
///     public var skills: [any AgentSkill] {
///         [SummarizeSkill(), TranslateSkill()]
///     }
/// }
/// ```
public protocol SkillKit: Sendable {
    /// SkillKit の識別名
    ///
    /// ログやデバッグ時の識別に使用されます。
    var name: String { get }

    /// この SkillKit が提供するスキルの配列
    ///
    /// SkillRegistry に追加される際、この配列のすべてのスキルが含まれます。
    var skills: [any AgentSkill] { get }
}

// MARK: - SkillKit Default Extensions

extension SkillKit {
    /// スキル数
    public var skillCount: Int {
        skills.count
    }

    /// スキル名のリスト
    public var skillNames: [String] {
        skills.map(\.name)
    }

    /// 名前でスキルを検索
    ///
    /// - Parameter name: スキル名
    /// - Returns: 見つかったスキル、またはnil
    public func skill(named name: String) -> (any AgentSkill)? {
        skills.first { $0.name == name }
    }
}
