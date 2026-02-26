import Testing
import Foundation
@testable import LLMSubAgent

// MARK: - Registration & Completion

@Test func testRegisterAndComplete() async {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(
        taskId: taskId,
        agentType: "researcher",
        description: "Test task",
        taskHandle: handle
    )

    // 完了前は .running
    let beforeStatus = await registry.getOutput(taskId: taskId)
    guard case .running = beforeStatus else {
        Issue.record("Expected .running but got \(String(describing: beforeStatus))")
        return
    }

    // 完了マーク
    await registry.markCompleted(taskId: taskId, result: "Done!")
    let afterStatus = await registry.getOutput(taskId: taskId)
    guard case .completed(let result) = afterStatus else {
        Issue.record("Expected .completed but got \(String(describing: afterStatus))")
        return
    }
    #expect(result == "Done!")
}

// MARK: - Failed Status

@Test func testRegisterAndFail() async {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(
        taskId: taskId,
        agentType: "researcher",
        description: "Failing task",
        taskHandle: handle
    )

    await registry.markFailed(taskId: taskId, error: "Something went wrong")
    let status = await registry.getOutput(taskId: taskId)
    guard case .failed(let error) = status else {
        Issue.record("Expected .failed but got \(String(describing: status))")
        return
    }
    #expect(error == "Something went wrong")
}

// MARK: - Unknown Task

@Test func testGetOutputForUnknownTask() async {
    let registry = BackgroundTaskRegistry()
    let status = await registry.getOutput(taskId: UUID())
    #expect(status == nil)
}

// MARK: - waitForOutput with Completion

@Test func testWaitForOutputCompletesInTime() async {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(
        taskId: taskId,
        agentType: "researcher",
        description: "Delayed task",
        taskHandle: handle
    )

    // 100ms 後に完了をマーク
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        await registry.markCompleted(taskId: taskId, result: "Delayed result")
    }

    let status = await registry.waitForOutput(taskId: taskId, timeout: .seconds(5))
    guard case .completed(let result) = status else {
        Issue.record("Expected .completed but got \(String(describing: status))")
        return
    }
    #expect(result == "Delayed result")
}

// MARK: - waitForOutput Timeout

@Test func testWaitForOutputTimeout() async {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(
        taskId: taskId,
        agentType: "researcher",
        description: "Long task",
        taskHandle: handle
    )

    // タイムアウトまで完了しない
    let status = await registry.waitForOutput(taskId: taskId, timeout: .milliseconds(100))
    guard case .running = status else {
        Issue.record("Expected .running but got \(String(describing: status))")
        return
    }
}

// MARK: - Cancel Task

@Test func testCancelTask() async {
    let registry = BackgroundTaskRegistry()
    let taskId = UUID()
    let handle = Task<Void, Never> {
        try? await Task.sleep(for: .seconds(60))
    }

    await registry.register(
        taskId: taskId,
        agentType: "researcher",
        description: "Cancellable task",
        taskHandle: handle
    )

    let cancelled = await registry.cancelTask(taskId: taskId)
    #expect(cancelled)

    let status = await registry.getOutput(taskId: taskId)
    guard case .failed(let error) = status else {
        Issue.record("Expected .failed but got \(String(describing: status))")
        return
    }
    #expect(error == "Cancelled")
}

@Test func testCancelUnknownTask() async {
    let registry = BackgroundTaskRegistry()
    let cancelled = await registry.cancelTask(taskId: UUID())
    #expect(!cancelled)
}

// MARK: - List Tasks

@Test func testListTasks() async {
    let registry = BackgroundTaskRegistry()

    let id1 = UUID()
    let id2 = UUID()
    let handle = Task<Void, Never> {}

    await registry.register(taskId: id1, agentType: "researcher", description: "Task 1", taskHandle: handle)
    // 登録順序を保証するため少し待つ
    try? await Task.sleep(for: .milliseconds(10))
    await registry.register(taskId: id2, agentType: "writer", description: "Task 2", taskHandle: handle)

    let tasks = await registry.listTasks()
    #expect(tasks.count == 2)
    #expect(tasks[0].description == "Task 1")
    #expect(tasks[1].description == "Task 2")
    #expect(tasks[0].agentType == "researcher")
    #expect(tasks[1].agentType == "writer")
}

// MARK: - Remove Finished

@Test func testRemoveFinished() async {
    let registry = BackgroundTaskRegistry()
    let handle = Task<Void, Never> {}

    let runningId = UUID()
    let completedId = UUID()
    let failedId = UUID()

    await registry.register(taskId: runningId, agentType: "a", description: "Running", taskHandle: handle)
    await registry.register(taskId: completedId, agentType: "b", description: "Completed", taskHandle: handle)
    await registry.register(taskId: failedId, agentType: "c", description: "Failed", taskHandle: handle)

    await registry.markCompleted(taskId: completedId, result: "done")
    await registry.markFailed(taskId: failedId, error: "err")

    await registry.removeFinished()

    let tasks = await registry.listTasks()
    #expect(tasks.count == 1)
    #expect(tasks[0].id == runningId)
}
