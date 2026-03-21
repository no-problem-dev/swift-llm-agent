import Testing
@testable import LLMSkill
import LLMTool
import LLMAgent

// MARK: - AgentSkillDefinition Tests

@Test func testSkillDefinitionDefaults() {
    let skill = AgentSkillDefinition(
        name: "test-skill",
        description: "A test skill",
        instructions: "Do something useful."
    )

    #expect(skill.name == "test-skill")
    #expect(skill.description == "A test skill")
    #expect(skill.executionMode == .inline)
    #expect(skill.instructions == "Do something useful.")
    #expect(skill.allowedTools == nil)
    #expect(skill.tools.isEmpty)
    #expect(skill.systemPrompt == nil)
    #expect(skill.configuration.maxSteps == AgentConfiguration.default.maxSteps)
    #expect(skill.isUserInvocable == true)
    #expect(skill.isModelInvocable == true)
    #expect(skill.argumentHint == nil)
    #expect(skill.metadata == nil)
}

@Test func testSkillDefinitionCustomConfiguration() {
    let config = AgentConfiguration(maxSteps: 20)

    let skill = AgentSkillDefinition(
        name: "custom",
        description: "Custom skill",
        executionMode: .fork,
        instructions: "Do the work.",
        allowedTools: ["read_file", "search"],
        configuration: config,
        invocationMode: .modelOnly,
        argumentHint: "[topic]",
        metadata: SkillMetadata(license: "MIT", author: "test")
    )

    #expect(skill.executionMode == .fork)
    #expect(skill.allowedTools == ["read_file", "search"])
    #expect(skill.configuration.maxSteps == 20)
    #expect(skill.isUserInvocable == false)
    #expect(skill.argumentHint == "[topic]")
    #expect(skill.metadata?.license == "MIT")
    #expect(skill.metadata?.author == "test")
}

@Test func testInlineSkillHasCorrectMode() {
    let skill = AgentSkillDefinition(
        name: "inline-skill",
        description: "Inline",
        executionMode: .inline,
        instructions: "Instructions here."
    )
    #expect(skill.executionMode == .inline)
}

@Test func testForkSkillHasCorrectMode() {
    let skill = AgentSkillDefinition(
        name: "fork-skill",
        description: "Fork",
        executionMode: .fork,
        instructions: "Instructions here."
    )
    #expect(skill.executionMode == .fork)
}

// MARK: - Protocol Default Tests

struct MinimalSkill: AgentSkill {
    var name: String { "minimal" }
    var description: String { "Minimal skill" }
    var executionMode: SkillExecutionMode { .inline }
    var instructions: String { "Just do it." }
}

@Test func testProtocolDefaults() {
    let skill = MinimalSkill()

    #expect(skill.allowedTools == nil)
    #expect(skill.tools.isEmpty)
    #expect(skill.systemPrompt == nil)
    #expect(skill.configuration.maxSteps == AgentConfiguration.default.maxSteps)
    #expect(skill.isUserInvocable == true)
    #expect(skill.isModelInvocable == true)
    #expect(skill.argumentHint == nil)
    #expect(skill.metadata == nil)
}

// MARK: - SkillExecutionMode Tests

@Test func testExecutionModeRawValues() {
    #expect(SkillExecutionMode.inline.rawValue == "inline")
    #expect(SkillExecutionMode.fork.rawValue == "fork")
}

@Test func testExecutionModeFromString() {
    #expect(SkillExecutionMode(rawValue: "inline") == .inline)
    #expect(SkillExecutionMode(rawValue: "fork") == .fork)
    #expect(SkillExecutionMode(rawValue: "unknown") == nil)
}

// MARK: - SkillMetadata Tests

@Test func testSkillMetadataEquality() {
    let meta1 = SkillMetadata(license: "MIT", author: "test")
    let meta2 = SkillMetadata(license: "MIT", author: "test")
    let meta3 = SkillMetadata(license: "Apache-2.0")

    #expect(meta1 == meta2)
    #expect(meta1 != meta3)
}
