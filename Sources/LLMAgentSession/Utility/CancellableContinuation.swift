import Foundation

/// キャンセル安全な Continuation ラッパー
///
/// `CheckedContinuation` の手動管理をカプセル化し、
/// タスクキャンセル時の自動クリーンアップと二重 resume 防止を提供する。
///
/// ## 設計
///
/// - `NSLock` によるスレッドセーフ（`onCancel` は任意スレッドで呼ばれるため）
/// - `isSettled` フラグで二重 resume を防止
/// - `withTaskCancellationHandler` でキャンセル時に自動 resume
///
/// ## 使用例
///
/// ```swift
/// let waiter = CancellableContinuation<String>()
///
/// // 待機側（throws — キャンセル時は CancellationError）
/// let result = try await waiter.wait()
///
/// // 応答側（同期 — actor 内から await 不要）
/// waiter.resume(returning: "Hello")
///
/// // キャンセル側（同期）
/// waiter.cancel()
/// ```
public final class CancellableContinuation<T: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var isSettled = false

    public init() {}

    /// 値が resume されるまで待機する
    ///
    /// タスクがキャンセルされた場合は `CancellationError` を投げる。
    /// - Returns: `resume(returning:)` で渡された値
    /// - Throws: `CancellationError` — タスクキャンセルまたは `cancel()` 呼び出し時
    public func wait() async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                defer { lock.unlock() }

                if isSettled {
                    // cancel() が wait() より先に呼ばれた場合
                    cont.resume(throwing: CancellationError())
                } else {
                    self.continuation = cont
                }
            }
        } onCancel: {
            // 任意スレッドから呼ばれる — lock で保護
            self.cancel()
        }
    }

    /// 値で resume する（冪等・同期）
    ///
    /// 既に resume または cancel 済みの場合は何もしない。
    public func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }

        guard !isSettled else { return }
        isSettled = true
        continuation?.resume(returning: value)
        continuation = nil
    }

    /// CancellationError で resume する（冪等・同期）
    ///
    /// 既に resume または cancel 済みの場合は何もしない。
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }

        guard !isSettled else { return }
        isSettled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
