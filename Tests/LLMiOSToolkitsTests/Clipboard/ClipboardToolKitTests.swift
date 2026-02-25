import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("ClipboardToolKit")
struct ClipboardToolKitTests {

    @Test("ToolKit が2つのツールを提供する")
    func toolCount() {
        let toolkit = ClipboardToolKit()
        #expect(toolkit.tools.count == 2)
        #expect(toolkit.name == "clipboard")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = ClipboardToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "get_clipboard",
            "set_clipboard",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = ClipboardToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("set_clipboard は text を必須にする")
    func setClipboardRequiredFields() {
        let toolkit = ClipboardToolKit()
        let tool = toolkit.tools.first { $0.toolName == "set_clipboard" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("text"))
    }

    @Test("get_clipboard は必須パラメータなし")
    func getClipboardRequiredFields() {
        let toolkit = ClipboardToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_clipboard" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }
}
