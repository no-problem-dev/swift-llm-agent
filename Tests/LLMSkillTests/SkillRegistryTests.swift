import Testing
@testable import LLMSkill
import LLMAgent

// MARK: - SkillRegistry Tests

@Test func testRegistryBuilderWithMultipleSkills() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarizes text",
            instructions: "Summarize..."
        )
        AgentSkillDefinition(
            name: "translate",
            description: "Translates text",
            instructions: "Translate..."
        )
    }

    #expect(registry.skills.count == 2)
    #expect(registry.skillNames == ["summarize", "translate"])
}

@Test func testRegistryLookupByName() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarizes text",
            instructions: "Summarize..."
        )
        AgentSkillDefinition(
            name: "translate",
            description: "Translates text",
            instructions: "Translate..."
        )
    }

    let found = registry.skill(named: "summarize")
    #expect(found != nil)
    #expect(found?.name == "summarize")
    #expect(found?.description == "Summarizes text")

    let notFound = registry.skill(named: "nonexistent")
    #expect(notFound == nil)
}

@Test func testRegistryBuilderConditional() {
    let enableSummarize = true
    let enableTranslate = false

    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "base",
            description: "Base skill",
            instructions: "Base..."
        )

        if enableSummarize {
            AgentSkillDefinition(
                name: "summarize",
                description: "Summarize",
                instructions: "..."
            )
        }

        if enableTranslate {
            AgentSkillDefinition(
                name: "translate",
                description: "Translate",
                instructions: "..."
            )
        }
    }

    #expect(registry.skills.count == 2)
    #expect(registry.skillNames == ["base", "summarize"])
}

@Test func testRegistryBuilderWithLoop() {
    let names = ["skill_a", "skill_b", "skill_c"]

    let registry = SkillRegistryDefinition {
        for name in names {
            AgentSkillDefinition(
                name: name,
                description: "Skill \(name)",
                instructions: "Do \(name)..."
            )
        }
    }

    #expect(registry.skills.count == 3)
    #expect(registry.skillNames == ["skill_a", "skill_b", "skill_c"])
}

@Test func testRegistryFromArray() {
    let skills: [any AgentSkill] = [
        AgentSkillDefinition(name: "a", description: "A", instructions: "..."),
        AgentSkillDefinition(name: "b", description: "B", instructions: "..."),
    ]

    let registry = SkillRegistryDefinition(skills: skills)
    #expect(registry.skills.count == 2)
}

@Test func testEmptyRegistry() {
    let registry = SkillRegistryDefinition { }

    #expect(registry.skills.isEmpty)
    #expect(registry.skillNames.isEmpty)
    #expect(registry.skill(named: "anything") == nil)
}

@Test func testModelInvocableFiltering() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "auto",
            description: "Auto invocable",
            instructions: "...",
            isModelInvocable: true
        )
        AgentSkillDefinition(
            name: "manual-only",
            description: "Manual only",
            instructions: "...",
            isModelInvocable: false
        )
    }

    let modelSkills = registry.modelInvocableSkills
    #expect(modelSkills.count == 1)
    #expect(modelSkills[0].name == "auto")
}

@Test func testUserInvocableFiltering() {
    let registry = SkillRegistryDefinition {
        AgentSkillDefinition(
            name: "user-visible",
            description: "Visible to user",
            instructions: "...",
            isUserInvocable: true
        )
        AgentSkillDefinition(
            name: "hidden",
            description: "Hidden from user",
            instructions: "...",
            isUserInvocable: false
        )
    }

    let userSkills = registry.userInvocableSkills
    #expect(userSkills.count == 1)
    #expect(userSkills[0].name == "user-visible")
}
