import Foundation
import Testing
@testable import LLMAgentSession
import LLMClient
import LLMTool

/// テスト用の最小 StructuredProtocol 準拠型
private struct TestOutput: StructuredProtocol, Equatable {
    let text: String
    static var jsonSchema: JSONSchema { .string() }
}

@Test func testAgentSessionImport() {
    #expect(Bool(true))
}

@Test func testSessionStatusProperties() {
    let status = SessionStatus.idle
    #expect(status.canRun == true)
    #expect(status.isActive == false)
    #expect(status.canCancel == false)
}

// MARK: - SessionStatus Tests

@Test func testSessionStatusRunning() {
    let status = SessionStatus.running
    #expect(status.isActive == true)
    #expect(status.isRunning == true)
    #expect(status.canCancel == true)
    #expect(status.canRun == false)
    #expect(status.canResume == false)
}

@Test func testSessionStatusIdleProperties() {
    let status = SessionStatus.idle
    #expect(status.canRun == true)
    #expect(status.canResume == true)
    #expect(status.canCancel == false)
    #expect(status.isActive == false)
    #expect(status.error == nil)
}

@Test func testSessionStatusFailed() {
    let status = SessionStatus.failed(error: "test error")
    #expect(status.canResume == true)
    #expect(status.canClear == true)
    #expect(status.canRun == false)
    #expect(status.error == "test error")
}

@Test func testSessionStatusDescription() {
    let idle = SessionStatus.idle
    #expect(idle.description == "idle")

    let running = SessionStatus.running
    #expect(running.description == "running")

    let paused = SessionStatus.paused
    #expect(paused.description == "paused")
}

// MARK: - SessionApprovalCache Tests

@Test func testSessionApprovalCacheInitiallyEmpty() async {
    let cache = SessionApprovalCache()
    let isApproved = await cache.isApproved("write_file")
    #expect(isApproved == false)
}

@Test func testSessionApprovalCacheApproveAndCheck() async {
    let cache = SessionApprovalCache()
    await cache.approve("write_file")
    let isApproved = await cache.isApproved("write_file")
    #expect(isApproved == true)

    let otherApproved = await cache.isApproved("edit_file")
    #expect(otherApproved == false)
}

@Test func testSessionApprovalCacheClear() async {
    let cache = SessionApprovalCache()
    await cache.approve("write_file")
    await cache.approve("edit_file")
    await cache.clear()
    let isApproved = await cache.isApproved("write_file")
    #expect(isApproved == false)
}

// MARK: - ToolExecutionDecision Tests

@Test func testToolExecutionDecisionAllow() {
    let decision = ToolExecutionDecision.allow
    if case .allow = decision {
        #expect(Bool(true))
    } else {
        Issue.record("Expected .allow")
    }
}

@Test func testToolExecutionDecisionDeny() {
    let decision = ToolExecutionDecision.deny(reason: "Not permitted")
    if case .deny(let reason) = decision {
        #expect(reason == "Not permitted")
    } else {
        Issue.record("Expected .deny")
    }
}

@Test func testToolExecutionDecisionRequiresApproval() {
    let request = ToolApprovalRequest(
        toolCall: ToolCall(id: "test-1", name: "write_file", arguments: Data()),
        reason: "Outside workspace"
    )
    let decision = ToolExecutionDecision.requiresApproval(request: request)
    if case .requiresApproval(let req) = decision {
        #expect(req.toolCall.name == "write_file")
        #expect(req.reason == "Outside workspace")
    } else {
        Issue.record("Expected .requiresApproval")
    }
}

// MARK: - ToolApprovalRequest Tests

@Test func testToolApprovalRequestEquatable() {
    let id = UUID()
    let call = ToolCall(id: "test-1", name: "write_file", arguments: Data())
    let request1 = ToolApprovalRequest(id: id, toolCall: call, reason: "test")
    let request2 = ToolApprovalRequest(id: id, toolCall: call, reason: "test")
    #expect(request1 == request2)
}

@Test func testToolApprovalRequestIdentifiable() {
    let request = ToolApprovalRequest(
        toolCall: ToolCall(id: "test-1", name: "write_file", arguments: Data()),
        reason: "test"
    )
    #expect(request.id != UUID()) // unique ID
}

// MARK: - ToolApprovalResponse Tests

@Test func testToolApprovalResponseCases() {
    let allow = ToolApprovalResponse.allow
    let allowForSession = ToolApprovalResponse.allowForSession
    let deny = ToolApprovalResponse.deny

    if case .allow = allow { #expect(Bool(true)) } else { Issue.record("Expected .allow") }
    if case .allowForSession = allowForSession { #expect(Bool(true)) } else { Issue.record("Expected .allowForSession") }
    if case .deny = deny { #expect(Bool(true)) } else { Issue.record("Expected .deny") }
}

// MARK: - SessionChannel Tests

@Test func testSessionChannelCreation() async {
    let channel = SessionChannel()
    await channel.close()
}
