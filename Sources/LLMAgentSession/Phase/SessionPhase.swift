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
///
/// ## 使用例
///
/// ```swift
/// for try await phase in session.run("調査して", model: .sonnet, outputType: ResearchResult.self) {
///     switch phase {
///     case .idle:
///         // 待機状態
///     case .running(let step):
///         // ステップに応じた UI 更新
///     case .awaitingInteraction(let request):
///         // インタラクション UI を表示
///         InteractionView(request: request) { response in
///             await session.respond(response)
///         }
///     case .paused:
///         // 「再開」ボタンを表示
///     case .completed(let output):
///         // 型安全に構造化された結果を使用
///         print(output.summary)
///     case .failed(let error):
///         // エラーメッセージと「再開」ボタンを表示
///     }
/// }
/// ```
public enum SessionPhase<Output: StructuredProtocol>: Sendable {
    /// 待機中（未開始、完了済み、または clear() 後）
    case idle

    /// 実行中（現在のステップを保持）
    ///
    /// - Parameter step: 現在実行中のステップ
    case running(step: AgentStep)

    /// インタラクション待ち
    ///
    /// InteractiveTool が検出され、ユーザーの応答を待機中。
    /// `respond()` で応答するとランループが再開される。
    case awaitingInteraction(request: InteractionRequest)

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
    ///
    /// `running` または `awaitingInteraction` の場合に `true`
    public var isActive: Bool {
        switch self {
        case .running, .awaitingInteraction:
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

    /// インタラクション要求（awaitingInteraction の場合のみ）
    public var interactionRequest: InteractionRequest? {
        if case .awaitingInteraction(let request) = self {
            return request
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
        case .awaitingInteraction(let request):
            let truncated = request.prompt.prefix(30)
            let typeName = String(describing: type(of: request.payload.rawValue))
            return "awaitingInteraction(\(typeName): \(truncated)\(request.prompt.count > 30 ? "..." : ""))"
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
