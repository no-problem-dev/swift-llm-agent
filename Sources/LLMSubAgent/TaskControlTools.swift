import Foundation
import LLMClient
import LLMTool

// MARK: - WaitTaskTool

/// バックグラウンドタスクの状態変化を待機するツール
public struct WaitTaskTool: Tool {
    private let controller: any SubAgentTaskControlling

    public init(controller: any SubAgentTaskControlling) {
        self.controller = controller
    }

    public var toolName: String { "wait_task" }

    public var toolDescription: String {
        "Waits for a background task to change state or complete. Use this after delegate_task or use_skill started a background task."
    }

    public var inputSchema: JSONSchema {
        .object(
            properties: [
                "task_id": .string(
                    description: "The ID of the task to wait for."
                ),
                "timeout_seconds": .integer(
                    description: "How long to wait before returning the current state (0-300)."
                ),
            ],
            required: ["task_id"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let args = try decode(argumentsData)
        guard let taskId = UUID(uuidString: args.taskId) else {
            return .error("Invalid task_id format: \"\(args.taskId)\"")
        }

        let timeout = max(0, min(args.timeoutSeconds ?? 0, 300))
        let info: SubAgentTaskInfo?
        if timeout == 0 {
            info = await controller.getTask(id: taskId)
        } else {
            info = await controller.waitForTask(id: taskId, timeout: .seconds(timeout))
        }

        guard let info else {
            return .error("Task not found: \"\(args.taskId)\"")
        }
        return .text(render(info))
    }
}

// MARK: - ResumeTaskTool

/// 一時停止中のバックグラウンドタスクを再開するツール
public struct ResumeTaskTool: Tool {
    private let controller: any SubAgentTaskControlling

    public init(controller: any SubAgentTaskControlling) {
        self.controller = controller
    }

    public var toolName: String { "resume_task" }

    public var toolDescription: String {
        "Resumes a paused background task. You can attach more instructions and update the timeout or step budget."
    }

    public var inputSchema: JSONSchema {
        .object(
            properties: [
                "task_id": .string(description: "The ID of the paused task."),
                "additional_instructions": .string(
                    description: "Optional new guidance for the next attempt."
                ),
                "timeout_seconds": .integer(
                    description: "Optional new wall-clock timeout in seconds (1-1800)."
                ),
                "max_steps": .integer(
                    description: "Optional new step budget."
                ),
                "await_timeout_seconds": .integer(
                    description: "If set, wait this many seconds after resuming before returning."
                ),
            ],
            required: ["task_id"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let args = try decode(argumentsData)
        guard let taskId = UUID(uuidString: args.taskId) else {
            return .error("Invalid task_id format: \"\(args.taskId)\"")
        }

        let resumed = await controller.resumeTask(
            id: taskId,
            additionalInstructions: args.additionalInstructions,
            timeout: parsedTimeout(args.timeoutSeconds),
            maxSteps: args.maxSteps
        )
        guard let resumed else {
            return .error("Task not found: \"\(args.taskId)\"")
        }

        let awaitTimeout = max(0, min(args.awaitTimeoutSeconds ?? 0, 300))
        if awaitTimeout > 0,
           let waited = await controller.waitForTask(id: taskId, timeout: .seconds(awaitTimeout)) {
            return .text(render(waited))
        }

        return .text(render(resumed))
    }
}

// MARK: - CancelTaskTool

/// バックグラウンドタスクをキャンセルするツール
public struct CancelTaskTool: Tool {
    private let controller: any SubAgentTaskControlling

    public init(controller: any SubAgentTaskControlling) {
        self.controller = controller
    }

    public var toolName: String { "cancel_task" }

    public var toolDescription: String {
        "Cancels a running or paused background task."
    }

    public var inputSchema: JSONSchema {
        .object(
            properties: [
                "task_id": .string(description: "The ID of the task to cancel.")
            ],
            required: ["task_id"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let args = try decode(argumentsData)
        guard let taskId = UUID(uuidString: args.taskId) else {
            return .error("Invalid task_id format: \"\(args.taskId)\"")
        }

        guard await controller.cancelTask(id: taskId) else {
            return .error("Task not found: \"\(args.taskId)\"")
        }

        guard let info = await controller.getTask(id: taskId) else {
            return .error("Task not found: \"\(args.taskId)\"")
        }
        return .text(render(info))
    }
}

// MARK: - ListTasksTool

/// 既知のバックグラウンドタスク一覧を返すツール
public struct ListTasksTool: Tool {
    private let controller: any SubAgentTaskControlling

    public init(controller: any SubAgentTaskControlling) {
        self.controller = controller
    }

    public var toolName: String { "list_tasks" }

    public var toolDescription: String {
        "Lists all known background tasks and their current state."
    }

    public var inputSchema: JSONSchema {
        .object(properties: [:], required: [])
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let tasks = await controller.listTasks()
        guard !tasks.isEmpty else {
            return .text("No background tasks.")
        }

        let rendered = tasks.map(render).joined(separator: "\n\n")
        return .text(rendered)
    }
}

// MARK: - Shared Helpers

private struct TaskControlArguments: Decodable {
    let taskId: String
    let timeoutSeconds: Int?
    let maxSteps: Int?
    let additionalInstructions: String?
    let awaitTimeoutSeconds: Int?
}

private func decode(_ data: Data) throws -> TaskControlArguments {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(TaskControlArguments.self, from: data)
}

private func parsedTimeout(_ timeoutSeconds: Int?) -> Duration? {
    guard let timeoutSeconds, timeoutSeconds > 0 else { return nil }
    return .seconds(min(timeoutSeconds, 1800))
}

private func render(_ info: SubAgentTaskInfo) -> String {
    var lines = [
        "task_id: \(info.id.uuidString)",
        "agent_type: \(info.agentType)",
        "description: \(info.description)",
        "attempt: \(info.attempt)/\(info.maxAttempts)",
    ]

    switch info.status {
    case .queued:
        lines.append("status: queued")
    case .running:
        lines.append("status: running")
    case .paused(let reason, let note):
        lines.append("status: paused")
        lines.append("pause_reason: \(reason.rawValue)")
        lines.append("note: \(note)")
    case .completed(let result):
        lines.append("status: completed")
        lines.append("result: \(result)")
    case .failed(let error):
        lines.append("status: failed")
        lines.append("error: \(error)")
    case .cancelled:
        lines.append("status: cancelled")
    }

    return lines.joined(separator: "\n")
}
