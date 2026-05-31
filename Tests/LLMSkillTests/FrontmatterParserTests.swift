import Testing
import Foundation
import StructuredDataCore
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

    #expect(frontmatter.string("name") == "test-skill")
    #expect(frontmatter.string("description") == "A test skill")
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

    #expect(frontmatter.stringArray("allowed-tools") == ["read_file", "search_code", "write_file"])
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

    #expect(frontmatter.stringArray("allowed-tools") == ["read_file", "search_code"])
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

    #expect(frontmatter.bool("user-invocable") == false)
    #expect(frontmatter.bool("disable-model-invocation") == true)
}

/// YAML 1.2 Core（structured-data の YAMLParser）は `yes`/`no` を真偽値ではなく
/// 文字列として扱う（"Norway problem" の修正）。真偽値は `true`/`false` のみ。
@Test func testYesNoAreStringsNotBooleans() throws {
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

    #expect(frontmatter.bool("user-invocable") == nil)
    #expect(frontmatter.string("user-invocable") == "yes")
    #expect(frontmatter.string("disable-model-invocation") == "no")
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

    #expect(frontmatter.string("name") == "test-skill")
    #expect(frontmatter.string("description") == "A test skill")
}

@Test func testParseNumericValues() throws {
    let content = """
        ---
        name: test
        description: Test
        display-order: 8
        ---

        Instructions here.
        """

    let (frontmatter, _) = try FrontmatterParser.parse(content)

    #expect(frontmatter.int("display-order") == 8)
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

    #expect(frontmatter.string("name") == "test")
    #expect(frontmatter.string("description") == "Test skill")
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
