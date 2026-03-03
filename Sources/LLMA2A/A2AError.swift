import Foundation

// MARK: - LLMA2AError

/// LLMA2Aモジュールのエラー
public enum LLMA2AError: Error, LocalizedError, Sendable {
    /// エージェント接続エラー
    case connectionFailed(agentName: String, underlying: Error)

    /// スキル取得エラー
    case skillFetchFailed(agentName: String, underlying: Error)

    /// メッセージ送信エラー
    case messageSendFailed(agentName: String, underlying: Error)

    /// タスク取得エラー
    case taskFetchFailed(taskId: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let name, let error):
            return "Failed to connect to A2A agent '\(name)': \(error.localizedDescription)"
        case .skillFetchFailed(let name, let error):
            return "Failed to fetch skills from A2A agent '\(name)': \(error.localizedDescription)"
        case .messageSendFailed(let name, let error):
            return "Failed to send message to A2A agent '\(name)': \(error.localizedDescription)"
        case .taskFetchFailed(let taskId, let error):
            return "Failed to fetch task '\(taskId)': \(error.localizedDescription)"
        }
    }
}

// MARK: - A2AIntegrationError

/// A2A統合エラー（ToolSet操作関連）
public enum A2AIntegrationError: Error, LocalizedError, Sendable {
    /// プレースホルダーは直接実行できない
    case placeholderCannotExecute(agentName: String)

    /// スキルが見つからない
    case skillNotFound(skillId: String, agentName: String)

    public var errorDescription: String? {
        switch self {
        case .placeholderCannotExecute(let name):
            return "A2A agent '\(name)' placeholder cannot be executed directly. Call resolvingA2AAgents() first."
        case .skillNotFound(let skill, let agent):
            return "Skill '\(skill)' not found in A2A agent '\(agent)'"
        }
    }
}
