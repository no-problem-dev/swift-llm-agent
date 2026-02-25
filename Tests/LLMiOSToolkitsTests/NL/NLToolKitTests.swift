import Testing
@testable import LLMiOSToolkits
import LLMTool

@Suite("NLToolKit")
struct NLToolKitTests {

    @Test("ToolKit が4つのツールを提供する")
    func toolCount() {
        let toolkit = NLToolKit()
        #expect(toolkit.tools.count == 4)
        #expect(toolkit.name == "nl")
    }

    @Test("提供されるツール名が正しい")
    func toolNames() {
        let toolkit = NLToolKit()
        let names = Set(toolkit.tools.map { $0.toolName })
        let expected: Set<String> = [
            "detect_language",
            "analyze_sentiment",
            "extract_entities",
            "tokenize",
        ]
        #expect(names == expected)
    }

    @Test("各ツールが inputSchema を持つ")
    func toolSchemas() {
        let toolkit = NLToolKit()
        for tool in toolkit.tools {
            #expect(tool.inputSchema.type == .object)
        }
    }

    @Test("detect_language は text を必須にする")
    func detectLanguageRequiredFields() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "detect_language" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("text"))
    }

    @Test("analyze_sentiment は text を必須にする")
    func analyzeSentimentRequiredFields() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "analyze_sentiment" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("text"))
    }

    @Test("extract_entities は text を必須にする")
    func extractEntitiesRequiredFields() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "extract_entities" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("text"))
    }

    @Test("tokenize は text を必須にする")
    func tokenizeRequiredFields() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "tokenize" }
        #expect(tool != nil)
        let required = Set(tool!.inputSchema.required ?? [])
        #expect(required.contains("text"))
    }

    @Test("tokenize の inputSchema が unit プロパティを含む")
    func tokenizeSchemaProperties() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "tokenize" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("text"))
        #expect(props.keys.contains("unit"))
    }

    @Test("analyze_sentiment の inputSchema が by_sentence プロパティを含む")
    func analyzeSentimentSchemaProperties() {
        let toolkit = NLToolKit()
        let tool = toolkit.tools.first { $0.toolName == "analyze_sentiment" }!
        let props = tool.inputSchema.properties ?? [:]
        #expect(props.keys.contains("text"))
        #expect(props.keys.contains("by_sentence"))
    }
}
