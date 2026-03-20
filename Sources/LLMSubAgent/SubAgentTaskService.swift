import Foundation
import LLMClient
import LLMTool
import LLMAgent

// MARK: - SubAgentTaskPauseReason

/// バックグラウンドサブエージェントが一時停止した理由
public enum SubAgentTaskPauseReason: String, Sendable, Codable, Equatable {
    /// 実行時間の予算を使い切った
    case deadlineExceeded
    /// ステップ予算を使い切った
    case stepLimitExceeded
    /// オーケストレーターからの明示的な再開待ち
    case awaitingResume
}

// MARK: - SubAgentTaskStatus

/// バックグラウンドサブエージェントの状態
public enum SubAgentTaskStatus: Sendable, Equatable {
    case queued
    case running
    case paused(reason: SubAgentTaskPauseReason, note: String)
    case completed(String)
    case failed(String)
    case cancelled
}

// MARK: - SubAgentTaskInfo

/// バックグラウンドサブエージェントの公開 DTO
public struct SubAgentTaskInfo: Sendable, Identifiable {
    public let id: UUID
    public let agentType: String
    public let description: String
    public let createdAt: Date
    public let updatedAt: Date
    public let attempt: Int
    public let maxAttempts: Int
    public let status: SubAgentTaskStatus

    public var isRunning: Bool {
        switch status {
        case .queued, .running:
            true
        case .paused, .completed, .failed, .cancelled:
            false
        }
    }
}

// MARK: - SubAgentTaskControlling

/// サブエージェントタスクの制御 API
public protocol SubAgentTaskControlling: Sendable {
    func getTask(id: UUID) async -> SubAgentTaskInfo?
    func waitForTask(id: UUID, timeout: Duration) async -> SubAgentTaskInfo?
    func listTasks() async -> [SubAgentTaskInfo]
    func resumeTask(
        id: UUID,
        additionalInstructions: String?,
        timeout: Duration?,
        maxSteps: Int?
    ) async -> SubAgentTaskInfo?
    @discardableResult
    func cancelTask(id: UUID) async -> Bool
}

// MARK: - SubAgentTaskService

/// バックグラウンドサブエージェントを管理する実行サービス
public actor SubAgentTaskService<Client: AgentCapableClient>: SubAgentTaskControlling
    where Client.Model: Sendable
{
    // MARK: - Internal Types

    private struct TaskDefinition {
        let agentType: String
        let description: String
        let model: Client.Model
        let tools: ToolSet
        let systemPrompt: SystemPrompt?
        var configuration: AgentConfiguration
        var timeout: Duration?
        let maxAttempts: Int
    }

    private struct TaskEntry {
        let id: UUID
        let createdAt: Date
        var updatedAt: Date
        var attempt: Int
        var status: SubAgentTaskStatus
        var messages: [LLMMessage]
        var definition: TaskDefinition
        var handle: Task<Void, Never>?
    }

    // MARK: - Properties

    private let client: Client
    private let eventHandler: SubAgentEventHandler?
    private var tasks: [UUID: TaskEntry] = [:]

    // MARK: - Init

    public init(
        client: Client,
        eventHandler: SubAgentEventHandler? = nil
    ) {
        self.client = client
        self.eventHandler = eventHandler
    }

    // MARK: - Foreground Execution

    /// フォアグラウンドでサブエージェントを実行
    public func runForeground(
        agentType: String,
        description: String,
        prompt: String,
        model: Client.Model,
        tools: ToolSet,
        systemPrompt: SystemPrompt?,
        configuration: AgentConfiguration,
        timeout: Duration?
    ) async throws -> String {
        let taskId = UUID()
        await eventHandler?(.started(taskId: taskId, agentType: agentType, description: description))

        do {
            let result = try await SubAgentRunner.run(
                client: client,
                model: model,
                messages: [.user(prompt)],
                tools: tools,
                systemPrompt: systemPrompt,
                configuration: configuration,
                timeout: timeout,
                taskId: taskId,
                eventHandler: eventHandler
            )
            return result.output
        } catch {
            await eventHandler?(.failed(taskId: taskId, error: error))
            throw error
        }
    }

    // MARK: - Background Execution

    /// バックグラウンドタスクを起動
    public func startTask(
        agentType: String,
        description: String,
        prompt: String,
        model: Client.Model,
        tools: ToolSet,
        systemPrompt: SystemPrompt?,
        configuration: AgentConfiguration,
        timeout: Duration?,
        maxStepsOverride: Int?,
        maxAttempts: Int
    ) async -> SubAgentTaskInfo {
        let taskId = UUID()
        let now = Date()
        let definition = TaskDefinition(
            agentType: agentType,
            description: description,
            model: model,
            tools: tools,
            systemPrompt: systemPrompt,
            configuration: applyMaxStepsOverride(maxStepsOverride, to: configuration.forBackground),
            timeout: timeout,
            maxAttempts: max(1, maxAttempts)
        )
        tasks[taskId] = TaskEntry(
            id: taskId,
            createdAt: now,
            updatedAt: now,
            attempt: 0,
            status: .queued,
            messages: [.user(prompt)],
            definition: definition,
            handle: nil
        )

        await eventHandler?(
            .backgroundTaskRegistered(
                taskId: taskId,
                agentType: agentType,
                description: description
            )
        )

        launchTask(
            id: taskId,
            additionalInstructions: nil,
            timeoutOverride: nil,
            maxStepsOverride: nil
        )

        return taskInfo(for: taskId) ?? SubAgentTaskInfo(
            id: taskId,
            agentType: agentType,
            description: description,
            createdAt: now,
            updatedAt: now,
            attempt: 0,
            maxAttempts: max(1, maxAttempts),
            status: .queued
        )
    }

    // MARK: - SubAgentTaskControlling

    public func getTask(id: UUID) -> SubAgentTaskInfo? {
        taskInfo(for: id)
    }

    public func waitForTask(id: UUID, timeout: Duration) async -> SubAgentTaskInfo? {
        let deadline = ContinuousClock.now + timeout
        var sleepMs: UInt64 = 100
        while ContinuousClock.now < deadline {
            guard let info = taskInfo(for: id) else { return nil }
            if !info.isRunning { return info }
            do {
                try await Task.sleep(for: .milliseconds(sleepMs))
                sleepMs = min(sleepMs * 2, 1000) // 100ms → 200ms → 400ms → 800ms → 1000ms
            } catch {
                // Task cancelled — return current state
                return taskInfo(for: id)
            }
        }
        return taskInfo(for: id)
    }

    public func listTasks() -> [SubAgentTaskInfo] {
        tasks.values
            .map { entry in
                SubAgentTaskInfo(
                    id: entry.id,
                    agentType: entry.definition.agentType,
                    description: entry.definition.description,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    attempt: entry.attempt,
                    maxAttempts: entry.definition.maxAttempts,
                    status: entry.status
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func resumeTask(
        id: UUID,
        additionalInstructions: String?,
        timeout: Duration?,
        maxSteps: Int?
    ) async -> SubAgentTaskInfo? {
        guard let entry = tasks[id] else { return nil }

        switch entry.status {
        case .paused:
            launchTask(
                id: id,
                additionalInstructions: additionalInstructions,
                timeoutOverride: timeout,
                maxStepsOverride: maxSteps
            )
            return taskInfo(for: id)
        case .queued, .running, .completed, .failed, .cancelled:
            return taskInfo(for: id)
        }
    }

    @discardableResult
    public func cancelTask(id: UUID) async -> Bool {
        guard var entry = tasks[id] else { return false }

        entry.handle?.cancel()
        entry.handle = nil
        entry.updatedAt = Date()
        entry.status = .cancelled
        tasks[id] = entry
        await eventHandler?(.cancelled(taskId: id))
        return true
    }

    // MARK: - Private

    private func taskInfo(for id: UUID) -> SubAgentTaskInfo? {
        guard let entry = tasks[id] else { return nil }
        return SubAgentTaskInfo(
            id: entry.id,
            agentType: entry.definition.agentType,
            description: entry.definition.description,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            attempt: entry.attempt,
            maxAttempts: entry.definition.maxAttempts,
            status: entry.status
        )
    }

    private func launchTask(
        id: UUID,
        additionalInstructions: String?,
        timeoutOverride: Duration?,
        maxStepsOverride: Int?
    ) {
        guard var entry = tasks[id], entry.handle == nil else { return }

        if let timeoutOverride {
            entry.definition.timeout = timeoutOverride
        }
        if let maxStepsOverride {
            entry.definition.configuration = applyMaxStepsOverride(maxStepsOverride, to: entry.definition.configuration)
        }

        if let additionalInstructions, !additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.messages.append(.user(additionalInstructions))
        }

        if entry.attempt > 0 {
            entry.messages.append(.user("Continue from the saved context and finish the remaining work."))
        }

        entry.attempt += 1
        entry.updatedAt = Date()
        entry.status = .running

        let attempt = entry.attempt
        let startingMessages = entry.messages
        let definition = entry.definition

        let handle = Task<Void, Never> { [weak self] in
            await self?.runBackgroundTask(
                id: id,
                attempt: attempt,
                startingMessages: startingMessages,
                definition: definition
            )
        }

        entry.handle = handle
        tasks[id] = entry
    }

    private func runBackgroundTask(
        id: UUID,
        attempt: Int,
        startingMessages: [LLMMessage],
        definition: TaskDefinition
    ) async {
        await eventHandler?(
            .started(
                taskId: id,
                agentType: definition.agentType,
                description: definition.description
            )
        )

        do {
            let result = try await SubAgentRunner.run(
                client: client,
                model: definition.model,
                messages: startingMessages,
                tools: definition.tools,
                systemPrompt: definition.systemPrompt,
                configuration: definition.configuration,
                timeout: definition.timeout,
                taskId: id,
                eventHandler: eventHandler
            )

            guard var entry = tasks[id], entry.status != .cancelled else { return }
            entry.handle = nil
            entry.updatedAt = Date()
            entry.messages = result.messages
            entry.status = .completed(result.output)
            tasks[id] = entry
        } catch let interruption as SubAgentRunInterruption {
            await pauseTask(
                id: id,
                attempt: attempt,
                interruption: interruption
            )
        } catch let error as SubAgentError {
            if case .maxStepsExceeded = error {
                await pauseTask(
                    id: id,
                    attempt: attempt,
                    interruption: SubAgentRunInterruption.stepLimitExceeded(messages: startingMessages)
                )
            } else {
                await failTask(id: id, error: error)
            }
        } catch {
            await failTask(id: id, error: error)
        }
    }

    private func pauseTask(
        id: UUID,
        attempt: Int,
        interruption: SubAgentRunInterruption
    ) async {
        guard var entry = tasks[id], entry.status != .cancelled else { return }

        entry.handle = nil
        entry.updatedAt = Date()
        entry.messages = interruption.messages

        let reason: SubAgentTaskPauseReason
        let note: String
        switch interruption {
        case .timedOut:
            reason = .deadlineExceeded
            note = "Task reached its wall-clock limit and can be resumed."
        case .stepLimitExceeded:
            reason = .stepLimitExceeded
            note = "Task reached its step budget and can be resumed."
        case .cancelled:
            entry.status = .cancelled
            tasks[id] = entry
            await eventHandler?(.cancelled(taskId: id))
            return
        }

        if attempt >= entry.definition.maxAttempts {
            let message = "Task exhausted its retry budget after \(attempt) attempts."
            entry.status = .failed(message)
            tasks[id] = entry
            await eventHandler?(.failed(taskId: id, error: SubAgentError.invalidArguments(message)))
            return
        }

        entry.status = .paused(reason: reason, note: note)
        tasks[id] = entry
        await eventHandler?(.paused(taskId: id, reason: reason, note: note))
    }

    private func failTask(id: UUID, error: any Error) async {
        guard var entry = tasks[id], entry.status != .cancelled else { return }
        entry.handle = nil
        entry.updatedAt = Date()
        entry.status = .failed(error.localizedDescription)
        tasks[id] = entry
        await eventHandler?(.failed(taskId: id, error: error))
    }

    private func applyMaxStepsOverride(
        _ maxSteps: Int?,
        to configuration: AgentConfiguration
    ) -> AgentConfiguration {
        guard let maxSteps, maxSteps > 0 else { return configuration }
        return AgentConfiguration(
            maxSteps: maxSteps,
            softMaxSteps: max(1, maxSteps - 2),
            autoExecuteTools: configuration.autoExecuteTools,
            maxDuplicateToolCalls: configuration.maxDuplicateToolCalls,
            maxToolCallsPerTool: configuration.maxToolCallsPerTool,
            maxInteractiveCalls: configuration.maxInteractiveCalls,
            thinkingMode: configuration.thinkingMode,
            skipFinalOutput: configuration.skipFinalOutput
        )
    }
}
