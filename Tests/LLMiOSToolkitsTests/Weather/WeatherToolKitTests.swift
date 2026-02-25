import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("WeatherToolKit")
struct WeatherToolKitTests {

    @Test("ToolKit が2つのツールを提供する")
    func toolCount() {
        let toolkit = WeatherToolKit()
        #expect(toolkit.tools.count == 2)
        #expect(toolkit.name == "weather")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = WeatherToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "get_current_weather",
            "get_forecast",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = WeatherToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("get_current_weather は必須パラメータなし（座標 or 地名のどちらか）")
    func getCurrentWeatherRequiredFields() {
        let toolkit = WeatherToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_current_weather" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("get_current_weather の inputSchema が全プロパティを含む")
    func getCurrentWeatherSchemaProperties() {
        let toolkit = WeatherToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_current_weather" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("latitude"))
        #expect(props.keys.contains("longitude"))
        #expect(props.keys.contains("location"))
    }

    @Test("get_forecast の inputSchema が days プロパティを含む")
    func getForecastSchemaProperties() {
        let toolkit = WeatherToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_forecast" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("latitude"))
        #expect(props.keys.contains("longitude"))
        #expect(props.keys.contains("location"))
        #expect(props.keys.contains("days"))
    }
}
