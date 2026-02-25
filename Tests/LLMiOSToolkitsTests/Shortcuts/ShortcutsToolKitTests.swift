import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("ShortcutsToolKit")
struct ShortcutsToolKitTests {

    @Test("ToolKit が2つのツールを提供する")
    func toolCount() {
        let toolkit = ShortcutsToolKit()
        #expect(toolkit.tools.count == 2)
        #expect(toolkit.name == "shortcuts")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = ShortcutsToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "run_shortcut",
            "open_shortcuts",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = ShortcutsToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("run_shortcut は name を必須にする")
    func runShortcutRequiredFields() {
        let toolkit = ShortcutsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "run_shortcut" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("name"))
    }

    @Test("open_shortcuts は必須パラメータなし")
    func openShortcutsRequiredFields() {
        let toolkit = ShortcutsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "open_shortcuts" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }
}
