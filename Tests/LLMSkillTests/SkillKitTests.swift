import Testing
import Foundation
@testable import LLMSkill
import LLMAgent

// MARK: - InteractiveSkillKit Tests

@Test func testInteractiveSkillKitName() {
    let kit = InteractiveSkillKit()
    #expect(kit.name == "interactive")
}

@Test func testInteractiveSkillCatalogLoadsBundledSkills() throws {
    let skills = try InteractiveSkillCatalog.loadBundledSkills()
    #expect(skills.count == 21)
    #expect(skills.first?.name == "scan")
    #expect(skills.last?.name == "create_agent")
}

@Test func testInteractiveSkillKitContainsEighteenSkills() {
    let kit = InteractiveSkillKit()
    #expect(kit.skillCount == 21)
}

@Test func testInteractiveSkillKitSkillNames() {
    let kit = InteractiveSkillKit()
    #expect(Set(kit.skillNames) == Set([
        "capture_to_tasks", "compare", "context_restart",
        "create_agent", "create_project", "create_skill",
        "decide", "digest", "draft",
        "explain", "focus", "journal",
        "learn", "meeting_prep", "morning",
        "next_action", "quick_note", "research",
        "scan", "session_recall", "untangle",
    ]))
}

@Test func testMorningSkillProperties() {
    let kit = InteractiveSkillKit()
    let skill = kit.skill(named: "morning")

    #expect(skill != nil)
    #expect(skill?.executionMode == .inline)
    #expect(skill?.isModelInvocable == false)
    #expect(skill?.instructions.contains("朝のブリーフィング") == true)
    #expect(skill?.metadata?.version == "3.0.0")
    #expect(skill?.metadata?.tags?.contains("morning") == true)
}

@Test func testNextActionSkillProperties() {
    let kit = InteractiveSkillKit()
    let skill = kit.skill(named: "next_action")

    #expect(skill != nil)
    #expect(skill?.executionMode == .inline)
    #expect(skill?.isModelInvocable == false)
    #expect(skill?.instructions.contains("次の一手") == true)
    #expect(skill?.metadata?.version == "3.0.0")
    #expect(skill?.metadata?.tags?.contains("action") == true)
}

@Test func testAllSkillsAreInlineMode() {
    let kit = InteractiveSkillKit()
    for skill in kit.skills {
        #expect(skill.executionMode == .inline, "Skill \(skill.name) should be inline mode")
        #expect(skill.isModelInvocable == false, "Skill \(skill.name) should not be model-invocable")
    }
}

@Test func testSkillKitLookupNonexistent() {
    let kit = InteractiveSkillKit()
    #expect(kit.skill(named: "nonexistent") == nil)
}

// MARK: - SkillRegistryBuilder + SkillKit Tests

@Test func testRegistryBuilderAcceptsSkillKit() {
    let registry = SkillRegistryDefinition {
        InteractiveSkillKit()
    }

    #expect(registry.skills.count == 21)
    #expect(registry.skill(named: "morning") != nil)
    #expect(registry.skill(named: "learn") != nil)
    #expect(registry.skill(named: "context_restart") != nil)
}

@Test func testRegistryBuilderMixesSkillKitAndIndividualSkills() {
    let registry = SkillRegistryDefinition {
        InteractiveSkillKit()
        AgentSkillDefinition(
            name: "custom",
            description: "Custom skill",
            instructions: "Do custom things."
        )
    }

    #expect(registry.skills.count == 22)
    #expect(registry.skill(named: "morning") != nil)
    #expect(registry.skill(named: "custom") != nil)
}

// MARK: - Custom SkillKit Test

private struct TestSkillKit: SkillKit {
    var name: String { "test-kit" }
    var skills: [any AgentSkill] {
        [
            AgentSkillDefinition(
                name: "skill-a",
                description: "Skill A",
                instructions: "Do A."
            ),
        ]
    }
}

@Test func testCustomSkillKit() {
    let kit = TestSkillKit()
    #expect(kit.name == "test-kit")
    #expect(kit.skillCount == 1)
    #expect(kit.skillNames == ["skill-a"])
}

@Test func testRegistryBuilderWithMultipleSkillKits() {
    let registry = SkillRegistryDefinition {
        InteractiveSkillKit()
        TestSkillKit()
    }

    #expect(registry.skills.count == 22)
    #expect(registry.skill(named: "skill-a") != nil)
}
