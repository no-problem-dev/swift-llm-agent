import Testing
import Foundation
@testable import LLMSkill
import LLMAgent

// MARK: - SkillLoader String Parse Tests

@Test func testParseFullSkillMd() throws {
    let content = """
        ---
        name: code-review
        description: Reviews code for quality and best practices
        context: fork
        allowed-tools:
          - read_file
          - search_code
        license: MIT
        author: test-author
        argument-hint: "[file-path]"
        ---

        # Code Review Instructions

        When reviewing code, check for:
        1. Correctness and logic errors
        2. Security vulnerabilities
        3. Performance concerns
        """

    let skill = try SkillLoader.parse(content: content)

    #expect(skill.name == "code-review")
    #expect(skill.description == "Reviews code for quality and best practices")
    #expect(skill.executionMode == .fork)
    #expect(skill.allowedTools == ["read_file", "search_code"])
    #expect(skill.metadata?.license == "MIT")
    #expect(skill.metadata?.author == "test-author")
    #expect(skill.argumentHint == "[file-path]")
    #expect(skill.instructions.contains("Code Review Instructions"))
    #expect(skill.instructions.contains("Correctness and logic errors"))
}

@Test func testMissingNameField() {
    let content = """
        ---
        description: A skill without a name
        ---

        Instructions here.
        """

    #expect(throws: SkillError.self) {
        try SkillLoader.parse(content: content)
    }
}

@Test func testMissingDescriptionField() {
    let content = """
        ---
        name: test-skill
        ---

        Instructions here.
        """

    #expect(throws: SkillError.self) {
        try SkillLoader.parse(content: content)
    }
}

@Test func testDefaultExecutionModeIsInline() throws {
    let content = """
        ---
        name: simple-skill
        description: A simple skill
        ---

        Do something.
        """

    let skill = try SkillLoader.parse(content: content)
    #expect(skill.executionMode == .inline)
}

@Test func testInvalidExecutionMode() {
    let content = """
        ---
        name: test-skill
        description: Test
        context: invalid_mode
        ---

        Instructions here.
        """

    #expect(throws: SkillError.self) {
        try SkillLoader.parse(content: content)
    }
}

@Test func testEmptyBody() {
    let content = """
        ---
        name: empty-skill
        description: Skill with empty body
        ---
        """

    #expect(throws: SkillError.self) {
        try SkillLoader.parse(content: content)
    }
}

@Test func testAllOptionalFieldsParsed() throws {
    let content = """
        ---
        name: full-skill
        description: A skill with all fields
        context: fork
        allowed-tools:
          - tool_a
          - tool_b
        user-invocable: false
        disable-model-invocation: true
        argument-hint: "[topic]"
        license: Apache-2.0
        author: dev-team
        version: "1.0"
        compatibility: "Requires Python 3.10+"
        ---

        Full instructions here.
        """

    let skill = try SkillLoader.parse(content: content)

    #expect(skill.name == "full-skill")
    #expect(skill.executionMode == .fork)
    #expect(skill.allowedTools == ["tool_a", "tool_b"])
    #expect(skill.isUserInvocable == false)
    #expect(skill.isModelInvocable == false)
    #expect(skill.argumentHint == "[topic]")
    #expect(skill.metadata?.license == "Apache-2.0")
    #expect(skill.metadata?.author == "dev-team")
    #expect(skill.metadata?.version == "1.0")
    #expect(skill.metadata?.compatibility == "Requires Python 3.10+")
}

@Test func testInlineExecutionModeFromContext() throws {
    let content = """
        ---
        name: inline-skill
        description: Inline skill
        context: inline
        ---

        Instructions for inline execution.
        """

    let skill = try SkillLoader.parse(content: content)
    #expect(skill.executionMode == .inline)
}

@Test func testDefaultInvocationControl() throws {
    let content = """
        ---
        name: default-control
        description: Default invocation control
        ---

        Instructions here.
        """

    let skill = try SkillLoader.parse(content: content)
    #expect(skill.isUserInvocable == true)
    #expect(skill.isModelInvocable == true)
}

// MARK: - SkillLoader Round-Trip Test

@Test func testRoundTripParseToRegistry() throws {
    let content = """
        ---
        name: summarize
        description: Summarizes text content
        ---

        Create a concise summary of the provided text.
        Use bullet points for key findings.
        """

    let skill = try SkillLoader.parse(content: content)

    let registry = SkillRegistryDefinition {
        skill
    }

    #expect(registry.skills.count == 1)
    #expect(registry.skill(named: "summarize") != nil)
    #expect(registry.skill(named: "summarize")?.instructions.contains("bullet points") == true)
}

// MARK: - SkillLoader File Tests

@Test func testLoadSkillsFromDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("skill-test-\(UUID().uuidString)")

    // テストディレクトリ構造を作成
    let skillDir1 = tempDir.appendingPathComponent("summarize")
    let skillDir2 = tempDir.appendingPathComponent("translate")

    try FileManager.default.createDirectory(at: skillDir1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillDir2, withIntermediateDirectories: true)

    let skill1Content = """
        ---
        name: summarize
        description: Summarizes text
        ---

        Create a concise summary.
        """

    let skill2Content = """
        ---
        name: translate
        description: Translates text
        context: fork
        ---

        Translate the given text.
        """

    try skill1Content.write(
        to: skillDir1.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
    try skill2Content.write(
        to: skillDir2.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let skills = try SkillLoader.loadSkills(from: tempDir)

    #expect(skills.count == 2)

    let names = Set(skills.map(\.name))
    #expect(names.contains("summarize"))
    #expect(names.contains("translate"))

    let translateSkill = skills.first { $0.name == "translate" }
    #expect(translateSkill?.executionMode == .fork)
}

@Test func testLoadSkillFromFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("skill-file-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let skillContent = """
        ---
        name: test-skill
        description: A test skill
        ---

        Test instructions here.
        """

    let fileURL = tempDir.appendingPathComponent("SKILL.md")
    try skillContent.write(to: fileURL, atomically: true, encoding: .utf8)

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let skill = try SkillLoader.loadSkill(from: fileURL)
    #expect(skill.name == "test-skill")
    #expect(skill.instructions.contains("Test instructions"))
}

@Test func testLoadFromNonexistentDirectory() throws {
    let nonexistent = URL(filePath: "/tmp/nonexistent-skill-dir-\(UUID().uuidString)")
    let skills = try SkillLoader.loadSkills(from: nonexistent)
    #expect(skills.isEmpty)
}
