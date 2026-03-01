import Foundation
import LLMAgent

/// SkillTool / DelegateTaskTool で共有されるユーティリティ
public enum SubAgentToolHelpers {
    /// タイムアウト秒数を Duration に変換（1-1800 の範囲に制限）
    public static func parsedTimeout(_ timeoutSeconds: Int?) -> Duration? {
        guard let timeoutSeconds, timeoutSeconds > 0 else { return nil }
        return .seconds(min(timeoutSeconds, 1800))
    }

    /// maxSteps オーバーライドを適用した AgentConfiguration を返す
    public static func applyMaxStepsOverride(
        _ maxSteps: Int?, to configuration: AgentConfiguration
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

    /// SubAgentTaskInfo をテキスト表現にレンダリング
    public static func renderTaskInfo(_ info: SubAgentTaskInfo) -> String {
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
        case .failed(let message):
            lines.append("status: failed")
            lines.append("error: \(message)")
        case .cancelled:
            lines.append("status: cancelled")
        }

        return lines.joined(separator: "\n")
    }
}
