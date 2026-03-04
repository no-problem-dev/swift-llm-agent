import Foundation
import LLMClient

// MARK: - CollaborationChannel

/// Slack #channel のようなメッセージハブ
///
/// 3 メンバー（user, orchestrator, uiAgent）が所属し、
/// 誰かがメッセージを投稿すると他の subscriber に配信される pub/sub モデル。
///
/// ## 使い方
///
/// ```swift
/// let channel = CollaborationChannel()
///
/// // メンバー登録
/// let uiStream = await channel.subscribe(as: "uiAgent")
///
/// // メッセージ投稿（sender 以外に配信）
/// await channel.post(.userInput(input), from: "user")
///
/// // ブロッキングリクエスト（CheckedContinuation パターン）
/// let response = await channel.requestInteraction(intent, from: "orchestrator")
/// ```
public actor CollaborationChannel {

    // MARK: - State

    /// append-only メッセージログ
    private var messages: [ChannelMessage] = []

    /// subscriber の continuation マップ（memberId → continuation）
    private var subscribers: [String: AsyncStream<ChannelMessage>.Continuation] = [:]

    /// 保留中のインタラクション continuation
    private var pendingInteractions: [String: CheckedContinuation<InteractionResponse, Never>] = [:]

    /// 保留中のツール承認 continuation
    private var pendingAuthorizations: [String: CheckedContinuation<ToolApprovalResponse, Never>] = [:]

    private var isClosed = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Pub/Sub API

    /// メッセージを投稿（sender 以外の全 subscriber に配信）
    public func post(_ content: ChannelContent, from sender: String) {
        guard !isClosed else { return }

        let message = ChannelMessage(sender: sender, content: content)
        messages.append(message)

        // sender 以外の subscriber に配信
        for (memberId, continuation) in subscribers where memberId != sender {
            continuation.yield(message)
        }
    }

    /// Subscriber 登録（AsyncStream を返す）
    ///
    /// 同じ memberId で再登録すると、前の subscription は finish される。
    public func subscribe(as memberId: String) -> AsyncStream<ChannelMessage> {
        // 既存の subscription を閉じる
        subscribers[memberId]?.finish()

        let (stream, continuation) = AsyncStream<ChannelMessage>.makeStream()
        subscribers[memberId] = continuation
        return stream
    }

    // MARK: - Blocking Request API

    /// インタラクション応答を要求し、応答が返されるまで block する
    ///
    /// チャンネルに `.requestInteraction` を投稿し、対応する
    /// `.interactionResponse` が投稿されるまで待機する。
    public func requestInteraction(_ intent: InteractionIntent, from sender: String) async -> InteractionResponse {
        guard !isClosed else {
            return InteractionResponse(requestId: "", content: .dismissed)
        }

        post(.requestInteraction(intent), from: sender)

        return await withCheckedContinuation { continuation in
            pendingInteractions[intent.id] = continuation
        }
    }

    /// ツール承認応答を要求し、応答が返されるまで block する
    public func requestAuthorization(_ request: ToolApprovalRequest, from sender: String) async -> ToolApprovalResponse {
        guard !isClosed else { return .deny }

        post(.requestAuthorization(request), from: sender)

        return await withCheckedContinuation { continuation in
            pendingAuthorizations[request.id.uuidString] = continuation
        }
    }

    // MARK: - Response Handling

    /// 応答メッセージを処理（チャンネルに投稿 + pending continuation を resolve）
    ///
    /// `.interactionResponse` / `.authorizationResponse` は通常のメッセージとして
    /// チャンネルに投稿されつつ、対応する pending continuation も resolve する。
    public func postResponse(_ content: ChannelContent, from sender: String) {
        guard !isClosed else { return }

        // チャンネルに投稿（他のメンバーが観測可能）
        let message = ChannelMessage(sender: sender, content: content)
        messages.append(message)
        for (memberId, continuation) in subscribers where memberId != sender {
            continuation.yield(message)
        }

        // pending continuation を resolve
        switch content {
        case .interactionResponse(let response, let requestId):
            if let continuation = pendingInteractions.removeValue(forKey: requestId) {
                continuation.resume(returning: response)
            }
        case .authorizationResponse(let response, let requestId):
            if let continuation = pendingAuthorizations.removeValue(forKey: requestId) {
                continuation.resume(returning: response)
            }
        default:
            break
        }
    }

    // MARK: - Lifecycle

    /// チャネルを閉じる
    ///
    /// 全 subscriber を finish し、保留中の continuation をデフォルト値で resume する。
    public func close() {
        guard !isClosed else { return }
        isClosed = true

        // 全 subscriber を finish
        for (_, continuation) in subscribers {
            continuation.finish()
        }
        subscribers.removeAll()

        // 保留中のインタラクション continuation を dismissed で resume
        for (_, continuation) in pendingInteractions {
            continuation.resume(returning: InteractionResponse(
                requestId: "",
                content: .dismissed
            ))
        }
        pendingInteractions.removeAll()

        // 保留中の認可 continuation を deny で resume
        for (_, continuation) in pendingAuthorizations {
            continuation.resume(returning: .deny)
        }
        pendingAuthorizations.removeAll()
    }
}
