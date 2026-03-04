import Foundation

// MARK: - SessionStatus

/// 会話型エージェントセッションのライフサイクル状態
///
/// セッションの現在の状態を表す型パラメータなしの enum です。
/// Actor 内部の状態管理および外部公開プロパティとして使用します。
///
/// インタラクション待ち・承認待ちは UIAgentEvent 経由で UI に通知され、
/// セッション自体はチャネルの block で待機するため running のまま。
///
/// ## 状態遷移図
///
/// ```
/// idle ─────── run() ────→ running
///    │                        │
///    │                        ├── cancel() ──────→ paused
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
    case idle

    /// 実行中（インタラクション/承認待ちも含む — チャネルで block 中）
    case running

    /// 一時停止（cancel後、再開可能）
    case paused

    /// エラー発生（再開可能）
    case failed(error: String)
}

// MARK: - Convenience Properties

extension SessionStatus {
    /// セッションが実行中かどうか
    public var isActive: Bool {
        if case .running = self {
            return true
        }
        return false
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

    /// `cancel()` が呼び出し可能かどうか
    public var canCancel: Bool {
        if case .running = self {
            return true
        }
        return false
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
        case .paused:
            return "paused"
        case .failed(let error):
            let truncated = error.prefix(30)
            return "failed(\(truncated)\(error.count > 30 ? "..." : ""))"
        }
    }
}
