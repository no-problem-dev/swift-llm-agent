import Foundation

// MARK: - SessionStatus

/// 会話型エージェントセッションのライフサイクル状態
///
/// セッションの現在の状態を表す型パラメータなしの enum です。
/// Actor 内部の状態管理および外部公開プロパティとして使用します。
///
/// ステップの詳細（thinking, toolCall 等）はストリーム経由の
/// `SessionPhase.running(step:)` でのみ配信し、この型では保持しません。
///
/// ## 状態遷移図
///
/// ```
/// idle ─────── run() ────→ running
///    │                        │
///    │                        ├── cancel() ──────→ paused
///    │                        │
///    │                        ├── InteractiveTool → awaitingInteraction
///    │                        │                         │
///    │                        │                         ├── respond() → running
///    │                        │                         └── cancel() → paused
///    │                        │
///    │                        ├── 正常完了 ─────→ idle
///    │                        │
///    │                        └── エラー ────────→ failed
///    │
///    └─ resume() ─→ running (会話履歴がある場合のみ)
///
/// paused ────── resume() ───→ running
///          └── clear() ────→ idle
///
/// failed ────── resume() ───→ running
///          └── clear() ────→ idle
/// ```
public enum SessionStatus: Sendable, Equatable {
    /// 待機中（未開始、完了済み、または clear() 後）
    ///
    /// 許可される操作: `run()`
    case idle

    /// 実行中
    ///
    /// 許可される操作: `interrupt()`, `cancel()`
    case running

    /// インタラクション待ち（InteractiveTool 起因）
    ///
    /// 許可される操作: `respond()`, `cancel()`
    case awaitingInteraction(request: InteractionRequest)

    /// 一時停止（cancel後、再開可能）
    ///
    /// 許可される操作: `resume()`, `clear()`
    case paused

    /// エラー発生（再開可能）
    ///
    /// 許可される操作: `resume()`, `clear()`
    case failed(error: String)
}

// MARK: - Convenience Properties

extension SessionStatus {
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

    /// `run()` が呼び出し可能かどうか
    public var canRun: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    /// `resume()` が呼び出し可能かどうか
    ///
    /// `idle`、`paused`、`failed` の場合に `true`。
    /// `idle` 状態で `resume()` を呼ぶ場合、会話履歴が必要です。
    public var canResume: Bool {
        switch self {
        case .idle, .paused, .failed:
            return true
        default:
            return false
        }
    }

    /// `interrupt()` が呼び出し可能かどうか
    public var canInterrupt: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    /// `respond()` が呼び出し可能かどうか
    public var canRespond: Bool {
        if case .awaitingInteraction = self {
            return true
        }
        return false
    }

    /// `cancel()` が呼び出し可能かどうか
    public var canCancel: Bool {
        switch self {
        case .running, .awaitingInteraction:
            return true
        default:
            return false
        }
    }

    /// `clear()` が呼び出し可能かどうか
    public var canClear: Bool {
        switch self {
        case .paused, .failed:
            return true
        default:
            return false
        }
    }

    /// インタラクション要求（awaitingInteraction の場合のみ）
    public var interactionRequest: InteractionRequest? {
        if case .awaitingInteraction(let request) = self {
            return request
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

extension SessionStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .awaitingInteraction(let request):
            let truncated = request.prompt.prefix(30)
            return "awaitingInteraction(\(truncated)\(request.prompt.count > 30 ? "..." : ""))"
        case .paused:
            return "paused"
        case .failed(let error):
            let truncated = error.prefix(30)
            return "failed(\(truncated)\(error.count > 30 ? "..." : ""))"
        }
    }
}
