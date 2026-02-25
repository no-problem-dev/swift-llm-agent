import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("CalendarToolKit")
struct CalendarToolKitTests {

    @Test("ToolKit が5つのツールを提供する")
    func toolCount() {
        let toolkit = CalendarToolKit()
        #expect(toolkit.tools.count == 5)
        #expect(toolkit.name == "calendar")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = CalendarToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "list_calendars",
            "search_events",
            "create_event",
            "search_reminders",
            "create_reminder",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = CalendarToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("search_events は start_date と end_date を必須にする")
    func searchEventsRequiredFields() {
        let toolkit = CalendarToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_events" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("start_date"))
        #expect(required.contains("end_date"))
    }

    @Test("create_event は title, start_date, end_date を必須にする")
    func createEventRequiredFields() {
        let toolkit = CalendarToolKit()
        let tool = toolkit.tools.first { $0.toolName == "create_event" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("title"))
        #expect(required.contains("start_date"))
        #expect(required.contains("end_date"))
    }

    @Test("create_reminder は title を必須にする")
    func createReminderRequiredFields() {
        let toolkit = CalendarToolKit()
        let tool = toolkit.tools.first { $0.toolName == "create_reminder" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("title"))
    }
}
