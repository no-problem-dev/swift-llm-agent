import Foundation

// MARK: - SessionError

/// セッション実行中に発生するエラー
///
/// `SessionStatus.failed` および `SessionPhase.failed` で使用される
/// 構造化エラー型。文字列化による情報劣化を防ぎ、エラーの種別に応じた
/// ハンドリングを型安全に行えるようにする。
public enum SessionError: Error, Sendable, Equatable, LocalizedError {
    /// 最大ステップ数を超過
    case maxStepsExceeded(steps: Int)

    /// セッションがキャンセルされた
    case cancelled

    /// 出力のデコードに失敗
    case decodingFailed(String)

    /// LLM エラー
    case llmError(String)

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
            self = .llmError(error.localizedDescription)
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
        case .llmError(let detail):
            return detail
        case .unexpected(let detail):
            return detail
        }
    }
}
