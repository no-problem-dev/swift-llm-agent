import Testing
@testable import LLMmacOSToolkits

@Suite("LLMmacOSToolkits")
struct LLMmacOSToolkitsTests {

    // MARK: - ShellToolKit

    @Test("ShellToolKit provides 1 tool")
    func shellToolKitToolCount() {
        let toolkit = ShellToolKit()
        #expect(toolkit.tools.count == 1)
        #expect(toolkit.toolNames == ["execute_shell"])
    }

    // MARK: - MacClipboardToolKit

    @Test("MacClipboardToolKit provides 2 tools")
    func macClipboardToolKitToolCount() {
        let toolkit = MacClipboardToolKit()
        #expect(toolkit.tools.count == 2)
        #expect(toolkit.toolNames.contains("get_clipboard"))
        #expect(toolkit.toolNames.contains("set_clipboard"))
    }

    // MARK: - AppControlToolKit

    @Test("AppControlToolKit provides 4 tools")
    func appControlToolKitToolCount() {
        let toolkit = AppControlToolKit()
        #expect(toolkit.tools.count == 4)
        #expect(toolkit.toolNames.contains("app_list_running"))
        #expect(toolkit.toolNames.contains("app_launch"))
        #expect(toolkit.toolNames.contains("app_activate"))
        #expect(toolkit.toolNames.contains("app_quit"))
    }

    // MARK: - SystemInfoToolKit

    @Test("SystemInfoToolKit provides 1 tool")
    func systemInfoToolKitToolCount() {
        let toolkit = SystemInfoToolKit()
        #expect(toolkit.tools.count == 1)
        #expect(toolkit.toolNames == ["get_system_info"])
    }
}
