import Foundation

// MARK: - BackgroundTaskStatus

/// バックグラウンドタスクの実行状態
public enum BackgroundTaskStatus: Sendable {
    /// 実行中
    case running
    /// 正常完了
    case completed(String)
    /// エラーで終了
    case failed(String)
}

// MARK: - BackgroundTaskInfo

/// バックグラウンドタスクの外部公開 DTO
public struct BackgroundTaskInfo: Sendable, Identifiable {
    public let id: UUID
    public let agentType: String
    public let description: String
    public let startedAt: Date
    public let status: BackgroundTaskStatus
}

// MARK: - BackgroundTaskError

/// バックグラウンドタスク固有のエラー
public enum BackgroundTaskError: Error, Sendable {
    case taskNotFound
    case timeout
}

// MARK: - BackgroundTaskRegistry

/// バックグラウンドで実行中のサブエージェントタスクを管理するレジストリ
///
/// `DelegateTaskTool` が `run_in_background: true` で起動したタスクを追跡し、
/// `BackgroundTaskOutputTool` から結果を取得できるようにする。
///
/// ```swift
/// let registry = BackgroundTaskRegistry()
///
/// // タスク登録
/// await registry.register(
///     taskId: taskId,
///     agentType: "researcher",
///     description: "AI trends research",
///     taskHandle: task
/// )
///
/// // 結果取得
/// let status = await registry.getOutput(taskId: taskId)
/// ```
public actor BackgroundTaskRegistry {

    // MARK: - Internal Types

    private struct TaskEntry {
        let agentType: String
        let description: String
        let startedAt: Date
        var status: BackgroundTaskStatus
        let taskHandle: Task<Void, Never>
    }

    // MARK: - State

    private var tasks: [UUID: TaskEntry] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Registration

    /// タスクを登録
    public func register(
        taskId: UUID,
        agentType: String,
        description: String,
        taskHandle: Task<Void, Never>
    ) {
        tasks[taskId] = TaskEntry(
            agentType: agentType,
            description: description,
            startedAt: Date(),
            status: .running,
            taskHandle: taskHandle
        )
    }

    /// タスクを完了としてマーク
    public func markCompleted(taskId: UUID, result: String) {
        tasks[taskId]?.status = .completed(result)
    }

    /// タスクを失敗としてマーク
    public func markFailed(taskId: UUID, error: String) {
        tasks[taskId]?.status = .failed(error)
    }

    // MARK: - Query

    /// タスクの状態を即座に返す
    public func getOutput(taskId: UUID) -> BackgroundTaskStatus? {
        tasks[taskId]?.status
    }

    /// タスクの完了を待機（ポーリング方式）
    ///
    /// 500ms 間隔でポーリングし、タスクが完了するか
    /// タイムアウトするまで待機する。
    public func waitForOutput(taskId: UUID, timeout: Duration) async -> BackgroundTaskStatus? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let status = tasks[taskId]?.status {
                switch status {
                case .completed, .failed:
                    return status
                case .running:
                    break
                }
            } else {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        // タイムアウト: 現在の状態を返す
        return tasks[taskId]?.status
    }

    /// 全タスクの情報を返す
    public func listTasks() -> [BackgroundTaskInfo] {
        tasks.map { id, entry in
            BackgroundTaskInfo(
                id: id,
                agentType: entry.agentType,
                description: entry.description,
                startedAt: entry.startedAt,
                status: entry.status
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    /// タスクをキャンセル
    ///
    /// - Returns: タスクが存在しキャンセルされた場合は `true`
    @discardableResult
    public func cancelTask(taskId: UUID) -> Bool {
        guard let entry = tasks[taskId] else { return false }
        entry.taskHandle.cancel()
        tasks[taskId]?.status = .failed("Cancelled")
        return true
    }

    /// 完了・失敗済みのタスクを削除
    public func removeFinished() {
        tasks = tasks.filter { _, entry in
            if case .running = entry.status { return true }
            return false
        }
    }
}
