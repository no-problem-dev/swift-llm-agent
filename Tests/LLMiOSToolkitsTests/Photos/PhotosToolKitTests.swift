import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("PhotosToolKit")
struct PhotosToolKitTests {

    @Test("ToolKit が3つのツールを提供する")
    func toolCount() {
        let toolkit = PhotosToolKit()
        #expect(toolkit.tools.count == 3)
        #expect(toolkit.name == "photos")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = PhotosToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "search_photos",
            "get_photo_metadata",
            "get_albums",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = PhotosToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("get_photo_metadata は id を必須にする")
    func getPhotoMetadataRequiredFields() {
        let toolkit = PhotosToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_photo_metadata" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("id"))
    }

    @Test("search_photos は必須パラメータなし（全件取得可能）")
    func searchPhotosRequiredFields() {
        let toolkit = PhotosToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_photos" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("search_photos の inputSchema が全プロパティを含む")
    func searchPhotosSchemaProperties() {
        let toolkit = PhotosToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_photos" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("start_date"))
        #expect(props.keys.contains("end_date"))
        #expect(props.keys.contains("media_type"))
        #expect(props.keys.contains("album_name"))
        #expect(props.keys.contains("limit"))
    }
}
