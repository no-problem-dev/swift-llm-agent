import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("HealthToolKit")
struct HealthToolKitTests {

    #if canImport(HealthKit)
    @Test("ToolKit が6つのツールを提供する")
    func toolCount() {
        let toolkit = HealthToolKit()
        #expect(toolkit.tools.count == 6)
        #expect(toolkit.name == "health")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = HealthToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "query_health_data",
            "get_health_summary",
            "query_sleep",
            "query_workouts",
            "query_mindfulness",
            "save_health_data",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = HealthToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("query_health_data は data_type, start_date, end_date を必須にする")
    func queryHealthDataRequiredFields() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "query_health_data" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("data_type"))
        #expect(required.contains("start_date"))
        #expect(required.contains("end_date"))
    }

    @Test("query_sleep は start_date, end_date を必須にする")
    func querySleepRequiredFields() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "query_sleep" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("start_date"))
        #expect(required.contains("end_date"))
    }

    @Test("query_mindfulness は start_date, end_date を必須にする")
    func queryMindfulnessRequiredFields() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "query_mindfulness" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("start_date"))
        #expect(required.contains("end_date"))
    }

    @Test("save_health_data は data_type と value を必須にする")
    func saveHealthDataRequiredFields() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "save_health_data" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("data_type"))
        #expect(required.contains("value"))
    }

    @Test("get_health_summary は必須パラメータなし")
    func getHealthSummaryRequiredFields() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_health_summary" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("query_health_data の description に睡眠データの案内がある")
    func queryHealthDataDescriptionMentionsSleep() {
        let toolkit = HealthToolKit()
        let tool = toolkit.tools.first { $0.toolName == "query_health_data" }
        #expect(tool != nil)
        #expect(tool!.toolDescription.contains("query_sleep"))
    }
    #else
    @Test("HealthKit 非対応プラットフォームでは空のツールリスト")
    func emptyOnUnsupported() {
        let toolkit = HealthToolKit()
        #expect(toolkit.tools.isEmpty)
        #expect(toolkit.name == "health")
    }
    #endif
}
