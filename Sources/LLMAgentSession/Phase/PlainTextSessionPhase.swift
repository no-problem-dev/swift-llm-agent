import Foundation
import LLMTool

// MARK: - PlainTextSessionPhase

/// プレーンテキストエージェントセッションのフェーズ
///
/// ツール実行ループは持つが、構造化出力（finalOutput）フェーズをスキップし、
/// テキストをそのまま返すエージェントセッション用のフェーズです。
///
/// `SessionPhase<Output>` との違い:
///
/// | 型 | finalOutput | 完了時の型 |
/// |---|---|---|
/// | `SessionPhase<Output>` | あり（JSON デコード） | `Output` |
/// | `PlainTextSessionPhase` | なし | `String` |
///
/// ## 使用例
///
/// ```swift
/// for try await phase in session.run(input: "調査して", model: spec) {
///     switch phase {
///     case .running(let step):
///         print("Step: \(step)")
///     case .completed(let text):
///         print("Result: \(text)")
///     default:
///         break
///     }
/// }
/// ```
public enum PlainTextSessionPhase: Sendable {
    /// 待機中（未開始、完了済み、または clear() 後）
    case idle

    /// 実行中（現在のステップを保持）
    ///
    /// - Parameter step: 現在実行中のステップ
    case running(step: AgentStep)

    /// ユーザーの回答待ち（インタラクティブモード）
    case awaitingUserInput(question: String)

    /// 一時停止（cancel後、再開可能）
    case paused

    /// 正常完了（プレーンテキスト）
    ///
    /// - Parameter text: 生成されたテキスト
    case completed(text: String)

    /// エラー発生（再開可能）
    case failed(error: String)
}

// MARK: - Equatable

extension PlainTextSessionPhase: Equatable {}

// MARK: - Convenience Properties

extension PlainTextSessionPhase {
    /// セッションが実行中かどうか
    public var isActive: Bool {
        switch self {
        case .running, .awaitingUserInput:
            return true
        default:
            return false
        }
    }

    /// 現在のステップ（running の場合のみ）
    public var currentStep: AgentStep? {
        if case .running(let step) = self {
            return step
        }
        return nil
    }

    /// 完了テキスト（completed の場合のみ）
    public var text: String? {
        if case .completed(let text) = self {
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

extension PlainTextSessionPhase: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "idle"
        case .running(let step):
            return "running(\(step))"
        case .awaitingUserInput(let question):
            let truncated = question.prefix(30)
            return "awaitingUserInput(\(truncated)\(question.count > 30 ? "..." : ""))"
        case .paused:
            return "paused"
        case .completed(let text):
            let truncated = text.prefix(30)
            return "completed(\(truncated)\(text.count > 30 ? "..." : ""))"
        case .failed(let error):
            let truncated = error.prefix(30)
            return "failed(\(truncated)\(error.count > 30 ? "..." : ""))"
        }
    }
}
