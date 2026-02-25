import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("DeviceToolKit")
struct DeviceToolKitTests {

    @Test("ToolKit が4つのツールを提供する")
    func toolCount() {
        let toolkit = DeviceToolKit()
        #expect(toolkit.tools.count == 4)
        #expect(toolkit.name == "device")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = DeviceToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "get_device_info",
            "get_screen_brightness",
            "set_screen_brightness",
            "open_settings",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = DeviceToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("set_screen_brightness は brightness を必須にする")
    func setScreenBrightnessRequiredFields() {
        let toolkit = DeviceToolKit()
        let tool = toolkit.tools.first { $0.toolName == "set_screen_brightness" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("brightness"))
    }

    @Test("get_device_info は必須パラメータなし")
    func getDeviceInfoRequiredFields() {
        let toolkit = DeviceToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_device_info" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }
}
