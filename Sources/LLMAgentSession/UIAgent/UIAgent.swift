import Foundation
import LLMClient
import AgentCommunication

// MARK: - UIAgent

/// チャンネルベースの UI エージェント
///
/// `Channel<String>` を購読し、チャンネル上のメッセージに応じて
/// UI 関心事を処理する独立エージェント。
///
/// ## チャンネル駆動アーキテクチャ
///
/// ユーザー入力はチャンネルに投稿され、オーケストレーターと UIAgent が
/// 同時にメッセージを受信して並行動作を開始する:
///
/// 1. **user メッセージ受信** → `.inputReceived` イベント発火（UIAgent アクティブ化）
/// 2. **orchestrator メッセージ受信** → `.generationStarted` イベント発火（UI 生成開始）
///
/// UIAgent はオーケストレーターに依存せず、チャンネルメッセージを
/// トリガーとして自律的に動作する。
///
/// ## 使い方
///
/// ```swift
/// let uiAgent = UIAgent(eventHandler: { event in
///     await MainActor.run { sessionAgent.handleUIAgentEvent(event) }
/// })
/// Task { await uiAgent.start(on: channel) }
/// ```
public actor UIAgent: ChannelAgent {
    public typealias EventHandler = @Sendable (UIAgentEvent) async -> Void

    public let agentId: String = "uiAgent"
    public private(set) var status: AgentStatus = .idle

    private var eventHandler: EventHandler
    private var channel: Channel<String>?

    /// ブロッキングインタラクション用の continuation（キャンセル安全）
    private var pendingInteraction: CancellableContinuation<InteractionResponse>?

    // MARK: - Initialization

    public init(
        eventHandler: @escaping EventHandler = { _ in }
    ) {
        self.eventHandler = eventHandler
    }

    /// イベントハンドラーを更新
    public func setEventHandler(_ handler: @escaping EventHandler) {
        self.eventHandler = handler
    }

    // MARK: - ChannelAgent

    /// チャンネルを購読してメッセージ待受を開始する（冪等）
    ///
    /// 内部で `channel.subscribe(as:)` を呼ぶため、
    /// subscribe 完了前に post されたメッセージは受信できない。
    /// タイミング制御が必要な場合は `listen(on:messages:)` を使用する。
    public func start(on channel: Channel<String>) async {
        guard status == .idle || status == .stopped else { return }
        let messageStream = await channel.subscribe(as: ParticipantID(rawValue: agentId))
        await listen(on: channel, messages: messageStream)
    }

    /// 事前に subscribe 済みのストリームでメッセージ待受を開始（冪等）
    public func listen(on channel: Channel<String>, messages: AsyncStream<AgentMessage<String>>) async {
        guard status == .idle || status == .stopped else { return }

        self.channel = channel
        status = .listening

        for await message in messages {
            guard !Task.isCancelled else { break }
            await handleChannelMessage(message)
        }

        status = .stopped
    }

    public func stop() async {
        status = .stopped
        pendingInteraction?.cancel()
        pendingInteraction = nil
    }

    // MARK: - Interaction

    /// アプリ層からのインタラクション応答を受け取る
    ///
    /// emit_interaction ツールの実行を再開し、応答をチャンネルに投稿する。
    public func respondToInteraction(_ response: InteractionResponse) {
        pendingInteraction?.resume(returning: response)
        pendingInteraction = nil
    }

    /// インタラクションを要求し、応答を待つ（ブロッキング）
    ///
    /// UIAgent の LLM ループ内からツール経由で呼ばれる。
    /// タスクキャンセル時は `.dismissed` レスポンスを返す。
    public func requestInteraction(_ intent: InteractionIntent) async -> InteractionResponse {
        await eventHandler(.interactionRequested(intent))
        let continuation = CancellableContinuation<InteractionResponse>()
        self.pendingInteraction = continuation
        do {
            return try await continuation.wait()
        } catch {
            return InteractionResponse(requestId: UUID(), content: .dismissed)
        }
    }

    // MARK: - Event Emission

    /// UIAgent イベントを外部に配信
    public func emit(_ event: UIAgentEvent) async {
        await eventHandler(event)
    }

    // MARK: - Channel Post

    /// チャンネルにテキストを投稿
    public func postToChannel(_ text: String) async {
        await channel?.post(text, from: ParticipantID(rawValue: agentId))
    }

    // MARK: - Private

    private func handleChannelMessage(_ message: AgentMessage<String>) async {
        switch message.sender {
        case "user":
            // ユーザー入力をチャンネル経由で受信 → アクティブ状態に
            status = .processing
            await eventHandler(.inputReceived(query: message.content))
            status = .listening

        case "orchestrator":
            // オーケストレーターの出力を受信 → UI 生成を起動
            status = .processing
            await eventHandler(.generationStarted(rawText: message.content))
            status = .listening

        default:
            break
        }
    }
}
