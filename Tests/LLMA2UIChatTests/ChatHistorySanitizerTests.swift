import Foundation
import LLMClient
import Testing
@testable import LLMA2UIChat

@Suite("ChatHistorySanitizer")
struct ChatHistorySanitizerTests {

    @Test("assistant text 内の <a2ui-json> ブロックを placeholder に置換")
    func replacesA2UIBlock() {
        let body = """
        Sure!
        <a2ui-json>{"version":"v0.9","createSurface":{"surfaceId":"s1","catalogId":"c"}}</a2ui-json>
        Done.
        """
        let sanitized = ChatHistorySanitizer.stripA2UIBlocks(in: body)
        #expect(!sanitized.contains("<a2ui-json>"))
        #expect(sanitized.contains(ChatHistorySanitizer.placeholder))
        #expect(sanitized.contains("Sure!"))
        #expect(sanitized.contains("Done."))
    }

    @Test("複数 <a2ui-json> ブロックを個別に置換")
    func replacesMultipleBlocks() {
        let body = """
        <a2ui-json>{"version":"v0.9","createSurface":{"surfaceId":"a","catalogId":"c"}}</a2ui-json>
        text
        <a2ui-json>{"version":"v0.9","updateComponents":{"surfaceId":"a","components":[]}}</a2ui-json>
        """
        let sanitized = ChatHistorySanitizer.stripA2UIBlocks(in: body)
        let count = sanitized.components(separatedBy: ChatHistorySanitizer.placeholder).count - 1
        #expect(count == 2)
        #expect(!sanitized.contains("<a2ui-json>"))
    }

    @Test("user role の message は変更しない")
    func leavesUserUnchanged() {
        let original = LLMMessage(
            role: .user,
            contents: [.text("<a2ui-json>untouched</a2ui-json>")]
        )
        let out = ChatHistorySanitizer.sanitize(original)
        if case .text(let s) = out.contents[0] {
            #expect(s.contains("<a2ui-json>"))
        } else {
            Issue.record("expected text content")
        }
    }

    @Test("assistant の toolUse / toolResult は変更しない")
    func leavesToolContentsUnchanged() {
        let original = LLMMessage(
            role: .assistant,
            contents: [
                .text("hello <a2ui-json>x</a2ui-json>"),
                .toolUse(id: "1", name: "t", input: Data()),
            ]
        )
        let out = ChatHistorySanitizer.sanitize(original)
        // text content は置換
        if case .text(let s) = out.contents[0] {
            #expect(!s.contains("<a2ui-json>"))
        } else {
            Issue.record("expected text content first")
        }
        // toolUse はそのまま
        if case .toolUse(let id, _, _) = out.contents[1] {
            #expect(id == "1")
        } else {
            Issue.record("expected toolUse content second")
        }
    }

    @Test("ブロックを含まない text は変更しない")
    func unchangedWhenNoBlock() {
        let text = "Just some text with no a2ui content."
        #expect(ChatHistorySanitizer.stripA2UIBlocks(in: text) == text)
    }
}
