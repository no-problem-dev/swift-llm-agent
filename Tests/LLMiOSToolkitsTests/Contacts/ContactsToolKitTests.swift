import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("ContactsToolKit")
struct ContactsToolKitTests {

    @Test("ToolKit が3つのツールを提供する")
    func toolCount() {
        let toolkit = ContactsToolKit()
        #expect(toolkit.tools.count == 3)
        #expect(toolkit.name == "contacts")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = ContactsToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "search_contacts",
            "get_contact",
            "create_contact",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = ContactsToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("search_contacts は query を必須にする")
    func searchContactsRequiredFields() {
        let toolkit = ContactsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_contacts" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("query"))
    }

    @Test("get_contact は id を必須にする")
    func getContactRequiredFields() {
        let toolkit = ContactsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "get_contact" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("id"))
    }

    @Test("create_contact は必須フィールドなし（バリデーションはハンドラ内）")
    func createContactRequiredFields() {
        let toolkit = ContactsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "create_contact" }
        #expect(tool != nil)
        let required = tool!.inputSchema.required ?? []
        #expect(required.isEmpty)
    }

    @Test("search_contacts の inputSchema が query と limit プロパティを含む")
    func searchContactsSchemaProperties() {
        let toolkit = ContactsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "search_contacts" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("query"))
        #expect(props.keys.contains("limit"))
    }

    @Test("create_contact の inputSchema が全プロパティを含む")
    func createContactSchemaProperties() {
        let toolkit = ContactsToolKit()
        let tool = toolkit.tools.first { $0.toolName == "create_contact" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("given_name"))
        #expect(props.keys.contains("family_name"))
        #expect(props.keys.contains("organization_name"))
        #expect(props.keys.contains("phone_numbers"))
        #expect(props.keys.contains("email_addresses"))
        #expect(props.keys.contains("note"))
    }
}
