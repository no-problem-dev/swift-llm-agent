import Foundation
import LLMClient
import AgentCommunication

// MARK: - OrchestratorAgent

/// チャンネルベースのオーケストレーターエージェント
///
/// `Channel<String>` を購読し、メッセージを受信すると LLM ループを起動する。
/// ユーザーへの直接インタラクションは行わず、UIAgent にチャンネル経由で依頼する。
///
/// ## 動作フロー
///
/// 1. チャンネルメッセージを受信
/// 2. `LLMMessage.user("[sender] text")` として会話履歴に挿入
/// 3. LLM ループを起動（idle 時）or コンテキスト挿入のみ（processing 時）
/// 4. LLM のテキスト応答をチャンネルに post
/// 5. ループ完了 → listening に戻る
public actor OrchestratorAgent: ChannelAgent {
    public let agentId = "orchestrator"

    public private(set) var status: AgentStatus = .idle

    private let session: any ChatSessionProtocol
    private var channel: Channel<String>?
    private var loopTask: Task<Void, Never>?

    /// 外部観測用のステップストリーム
    private var stepsContinuation: AsyncStream<SessionPhaseEvent>.Continuation?

    // MARK: - Initialization

    public init(session: any ChatSessionProtocol) {
        self.session = session
    }

    // MARK: - Step Stream

    /// SessionAgent が観測するステップストリームを生成
    ///
    /// `start(on:)` の前に呼び出し、返された stream を Task で消費する。
    public func makeStepStream() -> AsyncStream<SessionPhaseEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionPhaseEvent.self)
        self.stepsContinuation = continuation
        return stream
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
        loopTask?.cancel()
        loopTask = nil
        await session.cancel()
        stepsContinuation?.finish()
        status = .stopped
    }

    // MARK: - ChatSessionProtocol Proxy

    /// 現在のセッション（設定変更用）
    public var chatSession: any ChatSessionProtocol { session }

    // MARK: - Private

    private func handleChannelMessage(_ message: AgentMessage<String>) async {
        let contextText = "[\(message.sender)] \(message.content)"

        if status == .processing {
            // ループ実行中 → コンテキスト挿入のみ（次の LLM コールに含まれる）
            await session.injectContext(contextText)
        } else {
            // idle/listening → 新しい LLM ループを起動
            startLoop(text: contextText)
        }
    }

    private func startLoop(text: String) {
        status = .processing
        let session = self.session

        loopTask = Task { [weak self] in
            do {
                let input = LLMInput(text)
                for try await event in await session.send(input) {
                    guard let self else { break }
                    await self.yieldStep(event)

                    // completed イベント時にチャンネルに結果を投稿
                    if case .completed(let result) = event {
                        await self.postToChannel(result.markdown)
                    }
                }
            } catch is CancellationError {
                // キャンセルは正常
            } catch {
                guard let self else { return }
                await self.yieldStep(.failed(error: error.localizedDescription))
            }

            guard let self else { return }
            await self.finishLoop()
        }
    }

    private func yieldStep(_ event: SessionPhaseEvent) {
        stepsContinuation?.yield(event)
    }

    private func finishLoop() {
        status = .listening
        loopTask = nil
    }

    private func postToChannel(_ text: String) async {
        await channel?.post(text, from: agentId)
    }
}
