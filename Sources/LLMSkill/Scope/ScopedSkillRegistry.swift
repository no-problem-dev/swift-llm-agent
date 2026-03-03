import Foundation
import LLMAgent

// MARK: - ScopedSkill

/// スコープ情報付きのスキル
public struct ScopedSkill: Sendable {
    /// スキル定義
    public let skill: any AgentSkill
    /// スコープ
    public let scope: ItemScope

    public init(skill: any AgentSkill, scope: ItemScope) {
        self.skill = skill
        self.scope = scope
    }
}

// MARK: - ScopedSkillRegistry

/// 3層スコープマージ対応のスキルレジストリ
///
/// `project` > `global` > `builtIn` の優先度で同名スキルを解決します。
/// `SkillRegistry` プロトコルに準拠し、`SkillTool` にそのまま渡せます。
///
/// ## 使用例
///
/// ```swift
/// let registry = ScopedSkillRegistry(
///     builtIn: InteractiveSkillKit().skills,
///     global: globalCustomSkills,
///     project: projectCustomSkills
/// )
/// // 同名スキルはプロジェクト > グローバル > ビルトインの優先度
/// ```
public struct ScopedSkillRegistry: SkillRegistry {

    /// スコープ付きの全スキル（マージ・重複除去済み）
    public let scopedSkills: [ScopedSkill]

    /// `SkillRegistry` 準拠: マージ済みスキル一覧
    public var skills: [any AgentSkill] {
        scopedSkills.map(\.skill)
    }

    /// 3層スコープからマージ
    ///
    /// - Parameters:
    ///   - builtIn: ビルトインスキル（最低優先度）
    ///   - global: グローバルカスタムスキル
    ///   - project: プロジェクトカスタムスキル（最高優先度）
    public init(
        builtIn: [any AgentSkill] = [],
        global: [any AgentSkill] = [],
        project: [any AgentSkill] = []
    ) {
        var seen = Set<String>()
        var result: [ScopedSkill] = []

        // 高優先度から追加（同名は先勝ち）
        for skill in project {
            if seen.insert(skill.name).inserted {
                result.append(ScopedSkill(skill: skill, scope: .project))
            }
        }
        for skill in global {
            if seen.insert(skill.name).inserted {
                result.append(ScopedSkill(skill: skill, scope: .global))
            }
        }
        for skill in builtIn {
            if seen.insert(skill.name).inserted {
                result.append(ScopedSkill(skill: skill, scope: .builtIn))
            }
        }

        self.scopedSkills = result
    }
}
