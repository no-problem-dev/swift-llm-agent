import Foundation
import LLMClient
import AgentCommunication

// MARK: - UIAgent

/// チャンネルベースの UI エージェント
///
/// `Channel<String>` を購読し、オーケストレーターからのメッセージに応じて
/// UI ブロック生成やユーザーインタラクションを実行する。
///
/// ## 設計
///
/// UIAgent は LLM を内蔵し、チャンネルメッセージをコンテキストとして
/// UI 生成の判断を行う。emit_block / emit_interaction ツールを使い、
/// アプリ層に UI イベントを配信する。
///
/// ユーザーからのインタラクション応答は `respondToInteraction()` 経由で受け取り、
/// チャンネルに投稿してオーケストレーターに伝える。
///
/// ## 使い方
///
/// ```swift
/// let uiAgent = UIAgent(
///     session: uiSession,
///     eventHandler: { event in
///         await MainActor.run { sessionAgent.handleUIAgentEvent(event) }
///     }
/// )
/// Task { await uiAgent.start(on: channel) }
/// ```
public actor UIAgent: ChannelAgent {
    public typealias EventHandler = @Sendable (UIAgentEvent) async -> Void

    public let agentId: String = "uiAgent"
    public private(set) var status: AgentStatus = .idle

    private var eventHandler: EventHandler
    private var channel: Channel<String>?

    /// ブロッキングインタラクション用の continuation
    private var interactionContinuation: CheckedContinuation<InteractionResponse, Never>?

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

    public func start(on channel: Channel<String>) async {
        self.channel = channel
        let messageStream = await channel.subscribe(as: agentId)
        status = .listening

        for await message in messageStream {
            guard !Task.isCancelled else { break }
            await handleChannelMessage(message)
        }

        status = .stopped
    }

    public func stop() async {
        interactionContinuation?.resume(returning: InteractionResponse(requestId: "", content: .dismissed))
        interactionContinuation = nil
        status = .stopped
    }

    // MARK: - Interaction

    /// アプリ層からのインタラクション応答を受け取る
    ///
    /// emit_interaction ツールの実行を再開し、応答をチャンネルに投稿する。
    public func respondToInteraction(_ response: InteractionResponse) {
        interactionContinuation?.resume(returning: response)
        interactionContinuation = nil
    }

    /// インタラクションを要求し、応答を待つ（ブロッキング）
    ///
    /// UIAgent の LLM ループ内からツール経由で呼ばれる。
    public func requestInteraction(_ intent: InteractionIntent) async -> InteractionResponse {
        await eventHandler(.interactionRequested(intent))
        return await withCheckedContinuation { continuation in
            self.interactionContinuation = continuation
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
        await channel?.post(text, from: agentId)
    }

    // MARK: - Private

    private func handleChannelMessage(_ message: AgentMessage<String>) async {
        // orchestrator からのメッセージに反応して UI 生成を起動
        guard message.sender == "orchestrator" else { return }

        status = .processing

        // オーケストレーターのメッセージを UI 生成イベントとして通知
        await eventHandler(.generationStarted(rawText: message.content))

        status = .listening
    }
}
