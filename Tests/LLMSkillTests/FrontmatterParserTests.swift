import Testing
import Foundation
import LLMAgent

// MARK: - FrontmatterParser Tests

@Test func testParseSimpleFrontmatter() throws {
    let content = """
        ---
        name: test-skill
        description: A test skill
        ---

        # Instructions

        Do something useful.
        """

    let (frontmatter, body) = try FrontmatterParser.parse(content)

    #expect(frontmatter["name"] as? String == "test-skill")
    #expect(frontmatter["description"] as? String == "A test skill")
    #expect(body.contains("# Instructions"))
    #expect(body.contains("Do something useful."))
}

@Test func testParseWithArrayValues() throws {
    let content = """
        ---
        name: test
        description: Test
        allowed-tools:
          - read_file
          - search_code
          - write_file
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    let tools = frontmatter["allowed-tools"] as? [String]
    #expect(tools == ["read_file", "search_code", "write_file"])
}

@Test func testParseWithInlineArray() throws {
    let content = """
        ---
        name: test
        description: Test
        allowed-tools: [read_file, search_code]
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    let tools = frontmatter["allowed-tools"] as? [String]
    #expect(tools == ["read_file", "search_code"])
}

@Test func testParseWithBooleanValues() throws {
    let content = """
        ---
        name: test
        description: Test
        user-invocable: false
        disable-model-invocation: true
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    #expect(frontmatter["user-invocable"] as? Bool == false)
    #expect(frontmatter["disable-model-invocation"] as? Bool == true)
}

@Test func testParseWithYesNoBooleans() throws {
    let content = """
        ---
        name: test
        description: Test
        user-invocable: yes
        disable-model-invocation: no
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    #expect(frontmatter["user-invocable"] as? Bool == true)
    #expect(frontmatter["disable-model-invocation"] as? Bool == false)
}

@Test func testParseWithQuotedStrings() throws {
    let content = """
        ---
        name: "test-skill"
        description: 'A test skill'
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    #expect(frontmatter["name"] as? String == "test-skill")
    #expect(frontmatter["description"] as? String == "A test skill")
}

@Test func testMissingOpeningDelimiter() {
    let content = """
        name: test
        description: Test
        ---

        Instructions here.
        """

    #expect(throws: FrontmatterParseError.self) {
        try FrontmatterParser.parse(content)
    }
}

@Test func testMissingClosingDelimiter() {
    let content = """
        ---
        name: test
        description: Test

        Instructions here.
        """

    #expect(throws: FrontmatterParseError.self) {
        try FrontmatterParser.parse(content)
    }
}

@Test func testParseWithComments() throws {
    let content = """
        ---
        name: test
        # This is a comment
        description: Test skill
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    #expect(frontmatter["name"] as? String == "test")
    #expect(frontmatter["description"] as? String == "Test skill")
}

@Test func testParsePreservesBody() throws {
    let content = """
        ---
        name: test
        description: Test
        ---

        # Main Title

        Step 1: Do this.
        Step 2: Do that.

        ## Subsection

        More content here.
        """

    let (_, body) = try FrontmatterParser.parse(content)

    #expect(body.contains("# Main Title"))
    #expect(body.contains("Step 1: Do this."))
    #expect(body.contains("## Subsection"))
    #expect(body.contains("More content here."))
}
