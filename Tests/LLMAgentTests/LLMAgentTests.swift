import Testing
@testable import LLMAgent
import LLMClient

@Test func testAgentImport() {
    #expect(Bool(true))
}

@Test func testAgentConfigurationDefault() {
    let config = AgentConfiguration.default
    #expect(config.maxSteps == 10)
    #expect(config.autoExecuteTools == true)
    #expect(config.maxDuplicateToolCalls == 2)
    #expect(config.maxToolCallsPerTool == 5)
}
