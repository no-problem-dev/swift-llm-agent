import Testing
import Foundation
@testable import LLMSkill
import LLMAgent

// MARK: - BuiltInSkillKit Tests

@Test func testBuiltInSkillKitName() {
    let kit = BuiltInSkillKit()
    #expect(kit.name == "built-in")
}

@Test func testBuiltInSkillKitContainsTwoSkills() {
    let kit = BuiltInSkillKit()
    #expect(kit.skillCount == 2)
}

@Test func testBuiltInSkillKitSkillNames() {
    let kit = BuiltInSkillKit()
    #expect(kit.skillNames == ["summarize", "code-review"])
}

@Test func testSummarizeSkillProperties() {
    let kit = BuiltInSkillKit()
    let skill = kit.skill(named: "summarize")

    #expect(skill != nil)
    #expect(skill?.executionMode == .fork)
    #expect(skill?.instructions.contains("Summarization Instructions") == true)
    #expect(skill?.metadata?.version == "1.0.0")
    #expect(skill?.metadata?.tags?.contains("summarization") == true)
}

@Test func testCodeReviewSkillProperties() {
    let kit = BuiltInSkillKit()
    let skill = kit.skill(named: "code-review")

    #expect(skill != nil)
    #expect(skill?.executionMode == .fork)
    #expect(skill?.instructions.contains("Code Review Instructions") == true)
    #expect(skill?.configuration.maxSteps == 8)
    #expect(skill?.metadata?.tags?.contains("code") == true)
}

@Test func testSkillKitLookupNonexistent() {
    let kit = BuiltInSkillKit()
    #expect(kit.skill(named: "nonexistent") == nil)
}

// MARK: - SkillRegistryBuilder + SkillKit Tests

@Test func testRegistryBuilderAcceptsSkillKit() {
    let registry = SkillRegistryDefinition {
        BuiltInSkillKit()
    }

    #expect(registry.skills.count == 2)
    #expect(registry.skill(named: "summarize") != nil)
    #expect(registry.skill(named: "code-review") != nil)
}

@Test func testRegistryBuilderMixesSkillKitAndIndividualSkills() {
    let registry = SkillRegistryDefinition {
        BuiltInSkillKit()
        AgentSkillDefinition(
            name: "custom",
            description: "Custom skill",
            instructions: "Do custom things."
        )
    }

    #expect(registry.skills.count == 3)
    #expect(registry.skill(named: "summarize") != nil)
    #expect(registry.skill(named: "code-review") != nil)
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
        BuiltInSkillKit()
        TestSkillKit()
    }

    #expect(registry.skills.count == 3)
    #expect(registry.skill(named: "skill-a") != nil)
}
