import Foundation
import LLMClient

// MARK: - SessionError

/// セッション実行中に発生するエラー
///
/// `SessionStatus.failed` および `SessionPhase.failed` で使用される
/// 構造化エラー型。エラーの種別に応じた型安全なハンドリングを可能にする。
///
/// - Note: `llmError` は `LLMError` を直接保持し、UI 層でエラー種別に応じた
///   リトライ戦略やユーザー通知を実装可能にする（rateLimitExceeded vs unauthorized 等）。
public enum SessionError: Error, Sendable, LocalizedError {
    /// 最大ステップ数を超過
    case maxStepsExceeded(steps: Int)

    /// セッションがキャンセルされた
    case cancelled

    /// 出力のデコードに失敗
    case decodingFailed(String)

    /// LLM エラー（型情報を保持）
    case llmError(LLMError)

    /// 予期しないエラー
    case unexpected(String)

    /// `ConversationalAgentError` から変換
    public init(from agentError: ConversationalAgentError) {
        switch agentError {
        case .maxStepsExceeded(let steps):
            self = .maxStepsExceeded(steps: steps)
        case .outputDecodingFailed(let error):
            self = .decodingFailed(error.localizedDescription)
        case .llmError(let error):
            self = .llmError(error)
        case .sessionAlreadyRunning, .toolNotFound, .toolExecutionFailed, .invalidState:
            self = .unexpected(agentError.localizedDescription)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .maxStepsExceeded(let steps):
            return "Maximum steps (\(steps)) exceeded"
        case .cancelled:
            return "Session was cancelled"
        case .decodingFailed(let detail):
            return "Output decoding failed: \(detail)"
        case .llmError(let error):
            return error.localizedDescription
        case .unexpected(let detail):
            return detail
        }
    }
}

// MARK: - Equatable

extension SessionError: Equatable {
    public static func == (lhs: SessionError, rhs: SessionError) -> Bool {
        switch (lhs, rhs) {
        case (.maxStepsExceeded(let a), .maxStepsExceeded(let b)):
            return a == b
        case (.cancelled, .cancelled):
            return true
        case (.decodingFailed(let a), .decodingFailed(let b)):
            return a == b
        case (.llmError(let a), .llmError(let b)):
            return a.localizedDescription == b.localizedDescription
        case (.unexpected(let a), .unexpected(let b)):
            return a == b
        default:
            return false
        }
    }
}
