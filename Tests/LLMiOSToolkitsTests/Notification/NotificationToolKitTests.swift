import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("NotificationToolKit")
struct NotificationToolKitTests {

    @Test("ToolKit が3つのツールを提供する")
    func toolCount() {
        let toolkit = NotificationToolKit()
        #expect(toolkit.tools.count == 3)
        #expect(toolkit.name == "notification")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = NotificationToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "schedule_notification",
            "list_pending_notifications",
            "cancel_notification",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = NotificationToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("schedule_notification は title を必須にする")
    func scheduleNotificationRequiredFields() {
        let toolkit = NotificationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "schedule_notification" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("title"))
    }

    @Test("cancel_notification は identifier を必須にする")
    func cancelNotificationRequiredFields() {
        let toolkit = NotificationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "cancel_notification" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("identifier"))
    }

    @Test("list_pending_notifications は必須パラメータなし")
    func listPendingRequiredFields() {
        let toolkit = NotificationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "list_pending_notifications" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("schedule_notification の inputSchema が全プロパティを含む")
    func scheduleNotificationSchemaProperties() {
        let toolkit = NotificationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "schedule_notification" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("title"))
        #expect(props.keys.contains("body"))
        #expect(props.keys.contains("date"))
        #expect(props.keys.contains("delay_seconds"))
        #expect(props.keys.contains("identifier"))
    }
}
