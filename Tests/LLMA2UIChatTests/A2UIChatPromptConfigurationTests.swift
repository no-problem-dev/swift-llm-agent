import Testing
@testable import LLMA2UIChat

@Suite("A2UIChatPromptConfiguration")
struct A2UIChatPromptConfigurationTests {

    @Test("DeleteSurfaceMessage を allowedMessages から除外している")
    func deleteSurfaceExcluded() {
        let allowed = A2UIChatPromptConfiguration.allowedMessages
        #expect(allowed.contains("CreateSurfaceMessage"))
        #expect(allowed.contains("UpdateComponentsMessage"))
        #expect(allowed.contains("UpdateDataModelMessage"))
        #expect(!allowed.contains("DeleteSurfaceMessage"))
    }

    @Test("toUnderlying() で workflowRules に append-only 指示が追加される")
    func workflowRulesAppendsAppendOnlyHint() {
        let config = A2UIChatPromptConfiguration(role: "test role")
        let underlying = config.toUnderlying()
        let rules = underlying.workflowRules ?? ""
        #expect(rules.contains(A2UIChatPromptConfiguration.appendOnlyRules))
        #expect(rules.contains("NEW unique surfaceId"))
    }

    @Test("schema block が createSurface を含み deleteSurface を含まない")
    func schemaBlockShape() {
        let config = A2UIChatPromptConfiguration(role: "test")
        let underlying = config.toUnderlying()
        let block = underlying.promptBuilder.schemaBlock()
        #expect(block.contains("CreateSurfaceMessage"))
        #expect(!block.contains("\"DeleteSurfaceMessage\""))
    }

    @Test("useCompactBuilder=true では FunctionCall が schema から消える")
    func compactBuilderDropsFunctionCall() {
        let config = A2UIChatPromptConfiguration(role: "test", useCompactBuilder: true)
        let underlying = config.toUnderlying()
        let block = underlying.promptBuilder.schemaBlock()
        #expect(!block.contains("\"FunctionCall\""))
    }
}
