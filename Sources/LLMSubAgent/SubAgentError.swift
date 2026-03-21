import Foundation
import LLMClient

// MARK: - SubAgentError

/// サブエージェント実行固有のエラー
public enum SubAgentError: Error, Sendable {
    /// 最大ステップ数を超過
    case maxStepsExceeded(steps: Int)

    /// LLM が空の応答を返した
    case emptyResponse

    /// タイムアウト
    case timeout(Duration)

    /// LLMエラーをラップ
    case llmError(LLMError)

    /// 無効な引数
    case invalidArguments(String)

    /// 指定されたエージェントタイプが見つからない
    case agentTypeNotFound(String)
}

// MARK: - LocalizedError

extension SubAgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .maxStepsExceeded(let steps):
            return "Sub-agent exceeded maximum steps limit (\(steps))"
        case .emptyResponse:
            return "Sub-agent returned an empty response"
        case .timeout(let duration):
            return "Sub-agent timed out after \(duration)"
        case .llmError(let error):
            return "LLM error in sub-agent: \(error.localizedDescription)"
        case .invalidArguments(let message):
            return "Invalid arguments for sub-agent: \(message)"
        case .agentTypeNotFound(let agentType):
            return "Sub-agent type not found: \"\(agentType)\""
        }
    }
}
