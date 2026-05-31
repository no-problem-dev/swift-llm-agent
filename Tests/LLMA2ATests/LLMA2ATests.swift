import Foundation
import Testing
@testable import LLMA2A

@Test func a2aAgentInitialization() {
    let agent = A2AAgent(
        url: URL(string: "https://agent.example.com")!,
        name: "test-agent",
        authentication: .bearer("test-token")
    )

    #expect(agent.agentName == "test-agent")
    #expect(agent.agentURL.absoluteString == "https://agent.example.com")
}

@Test func a2aAgentDefaultName() {
    let agent = A2AAgent(
        url: URL(string: "https://my-agent.example.com/a2a")!
    )

    #expect(agent.agentName == "my-agent.example.com")
}

@Test func a2aTaskInfoProperties() {
    let taskInfo = A2ATaskInfo(
        id: "task-1",
        state: .completed,
        statusMessage: "Done",
        artifactTexts: ["Result 1", "Result 2"]
    )

    #expect(taskInfo.isCompleted)
    #expect(!taskInfo.isFailed)
    #expect(!taskInfo.isInputRequired)
    #expect(taskInfo.responseText == "Done\nResult 1\nResult 2")
}

@Test func a2aTaskInfoFailedState() {
    let taskInfo = A2ATaskInfo(id: "task-2", state: .failed)

    #expect(taskInfo.isFailed)
    #expect(!taskInfo.isCompleted)
    #expect(taskInfo.responseText.isEmpty)
}

@Test func a2aAgentInfoCreation() {
    let skills = [
        A2ASkillInfo(id: "translate", name: "Translate", description: "Translate text", tags: ["nlp"]),
        A2ASkillInfo(id: "summarize", name: "Summarize", description: nil, tags: []),
    ]

    let info = A2AAgentInfo(
        name: "TestAgent",
        description: "A test agent",
        version: "1.0.0",
        skills: skills,
        supportsStreaming: true
    )

    #expect(info.name == "TestAgent")
    #expect(info.skills.count == 2)
    #expect(info.supportsStreaming)
    #expect(!info.supportsPushNotifications)
}

@Test func a2aTaskStateTerminal() {
    #expect(A2ATaskState.rejected.isTerminal)
    #expect(A2ATaskState.completed.isTerminal)
    #expect(!A2ATaskState.working.isTerminal)
    #expect(!A2ATaskState.inputRequired.isTerminal)
}

@Test func a2aTaskInfoCarriesContextId() {
    let taskInfo = A2ATaskInfo(id: "t", contextId: "ctx-1", state: .working)
    #expect(taskInfo.contextId == "ctx-1")
    #expect(!taskInfo.isCompleted)
}

@Test func a2aSendResultTaskVariant() {
    let result = A2ASendResult.task(
        A2ATaskInfo(id: "t", contextId: "ctx-1", state: .completed, statusMessage: "Done")
    )
    #expect(result.responseText == "Done")
    #expect(!result.isFailed)
    #expect(result.contextId == "ctx-1")
    #expect(result.task?.id == "t")
    #expect(result.message == nil)
}

@Test func a2aSendResultMessageVariant() {
    let result = A2ASendResult.message(
        A2AMessageInfo(messageId: "m", contextId: "ctx-2", text: "hi")
    )
    #expect(result.responseText == "hi")
    #expect(!result.isFailed)
    #expect(result.contextId == "ctx-2")
    #expect(result.task == nil)
    #expect(result.message?.messageId == "m")
}
