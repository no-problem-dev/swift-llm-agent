import Foundation
import LLMClient
import LLMTool

// MARK: - BackgroundTaskOutputTool

/// バックグラウンドタスクの結果を取得するツール
///
/// `DelegateTaskTool` が `run_in_background: true` で起動したタスクの
/// 結果を LLM が取得するためのツール。
///
/// ```swift
/// let registry = BackgroundTaskRegistry()
/// let outputTool = BackgroundTaskOutputTool(registry: registry)
///
/// // ToolSet に追加
/// let tools = ToolSet {
///     delegateTool
///     outputTool
/// }
/// ```
public struct BackgroundTaskOutputTool: Tool {
    private let registry: BackgroundTaskRegistry

    // MARK: - Init

    /// BackgroundTaskOutputTool を初期化
    ///
    /// - Parameter registry: バックグラウンドタスクレジストリ
    public init(registry: BackgroundTaskRegistry) {
        self.registry = registry
    }

    // MARK: - Tool Protocol

    public var toolName: String { "task_output" }

    public var toolDescription: String {
        "Retrieves output from a running or completed background task. "
            + "Takes a task_id parameter identifying the task. "
            + "Returns the task output along with status information. "
            + "Use timeout_seconds > 0 to wait for task completion."
    }

    public var inputSchema: JSONSchema {
        .object(
            properties: [
                "task_id": .string(
                    description: "The ID of the background task to get output from."
                ),
                "timeout_seconds": .integer(
                    description: "Maximum wait time in seconds (0-300). "
                        + "If 0 or omitted, returns the current status immediately. "
                        + "If > 0, waits for the task to complete up to this duration."
                ),
            ],
            required: ["task_id"]
        )
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let args: Arguments
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            args = try decoder.decode(Arguments.self, from: argumentsData)
        } catch {
            return .error("Failed to decode arguments: \(error.localizedDescription)")
        }

        guard let taskId = UUID(uuidString: args.taskId) else {
            return .error("Invalid task_id format: \"\(args.taskId)\"")
        }

        let timeoutSeconds = args.timeoutSeconds ?? 0

        if timeoutSeconds > 0 {
            // ブロッキング待機
            let timeout = Duration.seconds(min(timeoutSeconds, 300))
            let status = await registry.waitForOutput(taskId: taskId, timeout: timeout)
            return resultFromStatus(status, taskId: args.taskId)
        } else {
            // 即座に返す
            let status = await registry.getOutput(taskId: taskId)
            return resultFromStatus(status, taskId: args.taskId)
        }
    }

    // MARK: - Private

    private func resultFromStatus(_ status: BackgroundTaskStatus?, taskId: String) -> ToolResult {
        guard let status else {
            return .error("Task not found: \"\(taskId)\"")
        }

        switch status {
        case .running:
            return .text("Task is still running. Use timeout_seconds to wait for completion.")
        case .completed(let result):
            return .text(result)
        case .failed(let error):
            return .error("Background task failed: \(error)")
        }
    }
}

// MARK: - Arguments

extension BackgroundTaskOutputTool {
    private struct Arguments: Decodable {
        let taskId: String
        let timeoutSeconds: Int?
    }
}
