import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("LocationToolKit")
struct LocationToolKitTests {

    @Test("ToolKit が4つのツールを提供する")
    func toolCount() {
        let toolkit = LocationToolKit()
        #expect(toolkit.tools.count == 4)
        #expect(toolkit.name == "location")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = LocationToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "get_current_location",
            "search_places",
            "get_directions",
            "geocode",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = LocationToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("search_places は query を必須にする")
    func searchPlacesRequiredFields() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_places" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("query"))
    }

    @Test("get_current_location は必須パラメータなし")
    func getCurrentLocationRequiredFields() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_current_location" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("get_directions は必須パラメータなし（現在地をデフォルト使用）")
    func getDirectionsRequiredFields() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_directions" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("geocode は必須パラメータなし（address or lat/lon のどちらかが必要）")
    func geocodeRequiredFields() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "geocode" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("search_places の inputSchema が全プロパティを含む")
    func searchPlacesSchemaProperties() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_places" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("query"))
        #expect(props.keys.contains("latitude"))
        #expect(props.keys.contains("longitude"))
        #expect(props.keys.contains("radius"))
        #expect(props.keys.contains("limit"))
    }

    @Test("get_directions の inputSchema が origin/destination プロパティを含む")
    func getDirectionsSchemaProperties() {
        let toolkit = LocationToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_directions" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("origin_latitude"))
        #expect(props.keys.contains("origin_longitude"))
        #expect(props.keys.contains("origin_address"))
        #expect(props.keys.contains("destination_latitude"))
        #expect(props.keys.contains("destination_longitude"))
        #expect(props.keys.contains("destination_address"))
        #expect(props.keys.contains("transport_type"))
    }
}
