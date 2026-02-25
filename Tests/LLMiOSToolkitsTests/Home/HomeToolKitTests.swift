import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("HomeToolKit")
struct HomeToolKitTests {

    #if canImport(HomeKit)
    @Test("ToolKit が5つのツールを提供する")
    func toolCount() {
        let toolkit = HomeToolKit()
        #expect(toolkit.tools.count == 5)
        #expect(toolkit.name == "home")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = HomeToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "list_devices",
            "get_device_status",
            "control_device",
            "list_scenes",
            "activate_scene",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = HomeToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("control_device は action を必須にする")
    func controlDeviceRequiredFields() {
        let toolkit = HomeToolKit()
        let tool = toolkit.tools.first { $0.toolName == "control_device" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("action"))
    }

    @Test("activate_scene は name を必須にする")
    func activateSceneRequiredFields() {
        let toolkit = HomeToolKit()
        let tool = toolkit.tools.first { $0.toolName == "activate_scene" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("name"))
    }
    #else
    @Test("HomeKit 非対応プラットフォームでは空のツールリスト")
    func emptyOnUnsupported() {
        let toolkit = HomeToolKit()
        #expect(toolkit.tools.isEmpty)
        #expect(toolkit.name == "home")
    }
    #endif
}
