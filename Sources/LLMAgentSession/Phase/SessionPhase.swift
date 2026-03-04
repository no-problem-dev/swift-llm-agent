import Foundation
import LLMClient

// MARK: - SessionPhase

/// 会話型エージェントセッションのフェーズ（型付き）
///
/// ストリームで流れるイベントを表す型パラメータ付きの enum です。
/// `completed` ケースで構造化された出力を型安全に取得できます。
///
/// - Parameter Output: 構造化出力の型
///
/// ## SessionStatus との違い
///
/// | 型 | 用途 | 型パラメータ |
/// |---|------|------------|
/// | `SessionStatus` | 内部状態 & 公開プロパティ | なし |
/// | `SessionPhase<Output>` | ストリームで流れるイベント | あり |
public enum SessionPhase<Output: StructuredProtocol>: Sendable {
    /// 待機中（未開始、完了済み、または clear() 後）
    case idle

    /// 実行中（現在のステップを保持）
    ///
    /// - Parameter step: 現在実行中のステップ
    case running(step: AgentStep)

    /// 一時停止（cancel後、再開可能）
    case paused

    /// 正常完了（構造化出力）
    ///
    /// - Parameter output: 型安全な構造化出力
    case completed(output: Output)

    /// 正常完了（プレーンテキスト）
    ///
    /// `skipFinalOutput` が有効な場合に使用。
    /// LLM のテキスト応答を JSON デコードせずそのまま返す。
    case completedText(text: String)

    /// エラー発生（再開可能）
    case failed(error: String)
}

// MARK: - Equatable

extension SessionPhase: Equatable where Output: Equatable {}

// MARK: - Convenience Properties

extension SessionPhase {
    /// セッションが実行中かどうか
    public var isActive: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

    /// 実行中かどうか（`running` の場合のみ）
    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    /// 現在のステップ（running の場合のみ）
    public var currentStep: AgentStep? {
        if case .running(let step) = self {
            return step
        }
        return nil
    }

    /// 構造化出力（completed の場合のみ）
    public var output: Output? {
        if case .completed(let output) = self {
            return output
        }
        return nil
    }

    /// プレーンテキスト出力（completedText の場合のみ）
    public var completedText: String? {
        if case .completedText(let text) = self {
            return text
        }
        return nil
    }

    /// エラー文字列（failed の場合のみ）
    public var error: String? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}

// MARK: - CustomStringConvertible

extension SessionPhase: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "idle"
        case .running(let step):
            return "running(\(step))"
        case .paused:
            return "paused"
        case .completed(let output):
            let outputStr = String(describing: output)
            let truncated = outputStr.prefix(30)
            return "completed(\(truncated)\(outputStr.count > 30 ? "..." : ""))"
        case .completedText(let text):
            let truncated = text.prefix(30)
            return "completedText(\(truncated)\(text.count > 30 ? "..." : ""))"
        case .failed(let error):
            let truncated = error.prefix(30)
            return "failed(\(truncated)\(error.count > 30 ? "..." : ""))"
        }
    }
}
