import Testing
@testable import LLMAgentSession
import LLMClient

@Test func testAgentSessionImport() {
    #expect(Bool(true))
}

@Test func testSessionStatusProperties() {
    let status = SessionStatus.idle
    #expect(status.canRun == true)
    #expect(status.isActive == false)
    #expect(status.canCancel == false)
}
