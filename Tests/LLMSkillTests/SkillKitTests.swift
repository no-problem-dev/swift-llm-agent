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
    #expect(skills.count == 15)
    #expect(skills.first?.name == "morning")
    #expect(skills.last?.name == "session_recall")
}

@Test func testInteractiveSkillKitContainsFourteenSkills() {
    let kit = InteractiveSkillKit()
    #expect(kit.skillCount == 15)
}

@Test func testInteractiveSkillKitSkillNames() {
    let kit = InteractiveSkillKit()
    #expect(kit.skillNames == [
        "morning", "journal", "plan", "research",
        "draft", "brainstorm", "decide", "learn",
        "next_action", "handoff_draft", "read_later_distill",
        "meeting_prep_light", "capture_to_tasks", "context_restart",
        "session_recall",
    ])
}

@Test func testMorningSkillProperties() {
    let kit = InteractiveSkillKit()
    let skill = kit.skill(named: "morning")

    #expect(skill != nil)
    #expect(skill?.executionMode == .inline)
    #expect(skill?.isModelInvocable == false)
    #expect(skill?.instructions.contains("朝のブリーフィング") == true)
    #expect(skill?.metadata?.version == "2.0.0")
    #expect(skill?.metadata?.tags?.contains("morning") == true)
}

@Test func testNextActionSkillProperties() {
    let kit = InteractiveSkillKit()
    let skill = kit.skill(named: "next_action")

    #expect(skill != nil)
    #expect(skill?.executionMode == .inline)
    #expect(skill?.isModelInvocable == false)
    #expect(skill?.instructions.contains("次の一手") == true)
    #expect(skill?.metadata?.version == "2.1.0")
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

    #expect(registry.skills.count == 15)
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

    #expect(registry.skills.count == 16)
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

    #expect(registry.skills.count == 16)
    #expect(registry.skill(named: "skill-a") != nil)
}
