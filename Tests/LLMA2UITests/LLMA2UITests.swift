import Foundation
import Testing

@testable import A2UICore
@testable import A2UIParser
@testable import LLMA2UI

@Suite("A2UIResponseParser")
struct A2UIResponseParserTests {

    @Test func successWithValidBlocks() {
        let text = """
        Here's a form:
        <a2ui-json>
        {"version": "v0.9", "createSurface": {"surfaceId": "s1", "catalogId": "basic"}}
        </a2ui-json>
        """
        let result = A2UIResponseParser.parse(text)
        if case .success(let parts) = result {
            #expect(parts.count == 2)
            #expect(parts[0].text == "Here's a form:")
            #expect(parts[1].messages?.count == 1)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func successWithTextOnly() {
        let text = "Just regular text, no A2UI blocks."
        let result = A2UIResponseParser.parse(text)
        if case .success(let parts) = result {
            #expect(parts.count == 1)
            #expect(parts[0].text != nil)
        } else {
            Issue.record("Expected success for plain text")
        }
    }

    @Test func failureWithMalformedJSON() {
        let text = """
        <a2ui-json>
        { this is not valid json at all
        </a2ui-json>
        """
        let result = A2UIResponseParser.parse(text)
        if case .failure(_, let errors) = result {
            #expect(!errors.isEmpty)
        } else {
            Issue.record("Expected failure for malformed JSON")
        }
    }

    @Test func failureWithUnclosedTag() {
        let text = """
        <a2ui-json>
        {"version": "v0.9", "createSurface": {"surfaceId": "s1"
        """
        let result = A2UIResponseParser.parse(text)
        if case .failure = result {
            // Expected: unclosed tag detected
        } else {
            Issue.record("Expected failure for unclosed tag")
        }
    }
}

@Suite("A2UIRetryPrompt")
struct A2UIRetryPromptTests {

    @Test func formatRetryPromptContainsErrorDetails() {
        let errors = [
            A2UIParseError(blockIndex: 0, rawJSON: "{bad json}", message: "Expected comma"),
        ]
        let prompt = A2UIResponseParser.formatRetryPrompt(originalText: "...", errors: errors)
        #expect(prompt.contains("Expected comma"))
        #expect(prompt.contains("<a2ui-json>"))
        #expect(prompt.contains("regenerate"))
    }

    @Test func formatRetryPromptWithMultipleErrors() {
        let errors = [
            A2UIParseError(blockIndex: 0, rawJSON: "", message: "Missing version field"),
            A2UIParseError(blockIndex: 1, rawJSON: "", message: "Unknown component type"),
        ]
        let prompt = A2UIResponseParser.formatRetryPrompt(originalText: "...", errors: errors)
        #expect(prompt.contains("Missing version field"))
        #expect(prompt.contains("Unknown component type"))
    }
}

@Suite("A2UIAgentConfiguration")
struct A2UIAgentConfigurationTests {

    @Test func defaultMaxRetries() {
        let config = A2UIAgentConfiguration.default
        #expect(config.maxParseRetries == 2)
    }

    @Test func customMaxRetries() {
        let config = A2UIAgentConfiguration(maxParseRetries: 5)
        #expect(config.maxParseRetries == 5)
    }
}
