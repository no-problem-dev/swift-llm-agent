import Foundation
import LLMAgent

// MARK: - InteractiveSkillKit

/// サブエージェント委譲型インタラクティブスキルキット
///
/// バンドルされた `SKILL.md` リソースを読み込み、interactive 系スキルを提供します。
/// スキル本文の正本は `Resources/InteractiveSkills/*/SKILL.md` にあります。
public struct InteractiveSkillKit: SkillKit {
    public let name = "interactive"
    public let skills: [any AgentSkill]

    public init() {
        self.skills = InteractiveSkillCatalog.loadInteractiveSkills()
    }
}
