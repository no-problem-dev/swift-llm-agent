import Foundation

// MARK: - SessionStatus

/// セッションのライフサイクル状態（SSOT）
///
/// 全レイヤー共通のセッション状態 enum。
/// `ConversationalAgentSession`（actor 内部）と `SessionAgent`（UI 層）の
/// 両方がこの型を使用する。
///
/// ## 状態遷移図
///
/// ```
/// idle ─────── run() ────→ running
///    │                        │
///    │                        ├── InteractiveTool ──→ interaction
///    │                        ├── ToolApproval ────→ authorization
///    │                        ├── cancel() ────────→ cancelled
///    │                        ├── 正常完了 ─────────→ completed
///    │                        └── エラー ──────────→ failed
///    │
///    └─ resume() ─→ running (会話履歴がある場合のみ)
///
/// interaction ── respond() ──→ running
/// authorization ─ respond() ─→ running
///
/// paused ──── resume() ───→ running
///         └── clear() ────→ idle
///
/// cancelled ── clear() ───→ idle
///
/// failed ──── resume() ───→ running
///         └── clear() ────→ idle
///
/// completed ── send() ────→ running (新ターン)
///          └── clear() ───→ idle
/// ```
public enum SessionStatus: Sendable, Equatable {
    /// 待機中（未開始、または clear() 後）
    case idle

    /// 実行中（LLM 処理中）
    case running

    /// インタラクション待ち（InteractiveTool 起因）
    case interaction(InteractionRequest)

    /// ツール実行承認待ち（ToolExecutionPolicy 起因）
    case authorization(ToolApprovalRequest)

    /// 一時停止（再開可能）
    case paused

    /// キャンセル済み（再開不可、clear で idle に戻る）
    case cancelled

    /// ターン正常完了
    case completed

    /// エラー発生（再開可能）
    case failed(SessionError)
}

// MARK: - Convenience Properties

extension SessionStatus {
    /// セッションがアクティブか（idle / completed / cancelled 以外）
    public var isActive: Bool {
        switch self {
        case .running, .interaction, .authorization, .paused: true
        default: false
        }
    }

    /// 実行中かどうか（`running` の場合のみ）
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// 完了したかどうか
    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    /// インタラクション中かどうか
    public var isInteracting: Bool {
        if case .interaction = self { return true }
        return false
    }

    /// 承認待ちかどうか
    public var isAuthorizing: Bool {
        if case .authorization = self { return true }
        return false
    }

    /// インタラクションリクエスト（あれば）
    public var interactionRequest: InteractionRequest? {
        if case .interaction(let request) = self { return request }
        return nil
    }

    /// 承認リクエスト（あれば）
    public var authorizationRequest: ToolApprovalRequest? {
        if case .authorization(let request) = self { return request }
        return nil
    }

    /// `run()` / `sendWithPrefill()` が呼び出し可能かどうか
    ///
    /// 新しいターンを開始できる状態かを判定する。
    /// アクティブに実行中（`.running`）の場合のみ不可。
    public var canRun: Bool {
        switch self {
        case .running: return false
        default: return true
        }
    }

    /// `resume()` が呼び出し可能かどうか
    ///
    /// - Note: `.idle` は含まない。会話履歴がない状態では `run()` を使用すること。
    public var canResume: Bool {
        switch self {
        case .paused, .failed, .cancelled: true
        default: false
        }
    }

    /// `interrupt()` が呼び出し可能かどうか
    public var canInterrupt: Bool {
        if case .running = self { return true }
        return false
    }

    /// `cancel()` が呼び出し可能かどうか
    public var canCancel: Bool {
        switch self {
        case .running, .interaction, .authorization: true
        default: false
        }
    }

    /// `clear()` が呼び出し可能かどうか
    public var canClear: Bool {
        switch self {
        case .paused, .cancelled, .failed, .completed: true
        default: false
        }
    }

    /// エラー（failed の場合のみ）
    public var error: SessionError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    /// デバッグ用ラベル
    public var debugLabel: String { description }
}

// MARK: - CustomStringConvertible

extension SessionStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .interaction: return "interaction"
        case .authorization: return "authorization"
        case .paused: return "paused"
        case .cancelled: return "cancelled"
        case .completed: return "completed"
        case .failed(let error):
            let desc = error.localizedDescription
            let truncated = desc.prefix(30)
            return "failed(\(truncated)\(desc.count > 30 ? "..." : ""))"
        }
    }
}
