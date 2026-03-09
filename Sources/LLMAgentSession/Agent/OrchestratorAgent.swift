import Foundation
import LLMClient
import AgentCommunication

// MARK: - OrchestratorAgent

/// チャンネルベースのオーケストレーターエージェント
///
/// `Channel<String>` を購読し、メッセージを受信すると LLM ループを起動する。
/// ユーザーへの直接インタラクションは行わず、UIAgent にチャンネル経由で依頼する。
///
/// ## チャンネル駆動アーキテクチャ
///
/// ユーザー入力・他エージェントのメッセージは全てチャンネル経由で受信する:
///
/// 1. チャンネルメッセージを受信
/// 2. idle/listening → 新しい LLM ループを起動
/// 3. processing → コンテキスト挿入（次の LLM コールに含まれる）
/// 4. LLM の最終応答をチャンネルに post
/// 5. ループ完了 → listening に戻る
///
/// ## 冪等性
///
/// `start(on:)` は冪等。既に listening/processing 中なら何もしない。
/// チャンネルメッセージが自動的にループ起動 or コンテキスト挿入を判断する。
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

    /// チャンネルを購読してメッセージ待受を開始する（冪等）
    ///
    /// 内部で `channel.subscribe(as:)` を呼ぶため、
    /// subscribe 完了前に post されたメッセージは受信できない。
    /// タイミング制御が必要な場合は `listen(on:messages:)` を使用する。
    public func start(on channel: Channel<String>) async {
        guard status == .idle || status == .stopped else { return }
        let messageStream = await channel.subscribe(as: agentId)
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
        loopTask?.cancel()
        loopTask = nil
        await session.cancel()
        stepsContinuation?.finish()
        status = .stopped
    }

    // MARK: - ChatSessionProtocol Proxy

    /// 設定変更用のセッション参照
    ///
    /// `syncTurnConfiguration()` や `getSerializedMessages()` 等、
    /// LLM ループ外の操作に使用する。
    public var chatSession: any ChatSessionProtocol { session }

    // MARK: - Direct Commands

    /// スキル実行（prefill 注入 → LLM ループ起動）
    ///
    /// チャンネル経由ではなく、プログラム的にスキルの prefill を注入して
    /// LLM ループを起動する。ループの結果はチャンネルに投稿される。
    public func executeSkill(prefill: [LLMMessage]) {
        guard status != .processing else { return }
        startEventLoop { session in
            await session.sendWithPrefill(prefill)
        }
    }

    /// セッション再開（paused 状態から復帰）
    public func resume() {
        guard status != .processing else { return }
        startEventLoop { session in
            await session.resume()
        }
    }

    /// 割り込みメッセージを注入
    public func interrupt(_ message: String) async {
        await session.interrupt(message)
    }

    /// 実行中のループをキャンセル
    ///
    /// ループをキャンセルし listening 状態に戻る（エージェント自体は停止しない）。
    public func cancelLoop() async {
        loopTask?.cancel()
        loopTask = nil
        await session.cancel()
        if status == .processing {
            status = .listening
        }
    }

    /// 会話履歴をクリア
    public func clear() async {
        loopTask?.cancel()
        loopTask = nil
        await session.clear()
        if status == .processing {
            status = .listening
        }
    }

    // MARK: - Private

    private func handleChannelMessage(_ message: AgentMessage<String>) async {
        let contextText = "[\(message.sender)] \(message.content)"

        if status == .processing {
            await session.injectContext(contextText)
        } else {
            startLoop(text: contextText)
        }
    }

    private func startLoop(text: String) {
        startEventLoop { session in
            let input = LLMInput(text)
            return await session.send(input)
        }
    }

    /// LLM ループの共通実行ロジック
    ///
    /// `send` / `sendWithPrefill` / `resume` の違いはストリーム取得方法のみ。
    /// イベント処理・チャンネル投稿・エラーハンドリングは共通化する。
    private func startEventLoop(
        streamFactory: @escaping @Sendable (any ChatSessionProtocol) async -> AsyncThrowingStream<SessionPhaseEvent, Error>
    ) {
        status = .processing
        let session = self.session

        loopTask = Task { [weak self] in
            do {
                var didComplete = false
                var lastText: String?
                var didPostToChannel = false

                for try await event in await streamFactory(session) {
                    guard let self else { break }
                    await self.yieldStep(event)

                    switch event {
                    case .completed(let result):
                        didComplete = true
                        await self.postToChannel(result.markdown)
                    case .textDelta(let delta):
                        lastText = (lastText ?? "") + delta
                    case .toolCall(let name, _):
                        if name == "post_to_channel" {
                            didPostToChannel = true
                        }
                    default:
                        break
                    }
                }

                // skipFinalOutput 時: .completed が来ないため最後のテキストを投稿
                // ただし post_to_channel を明示的に呼んだ場合は二重投稿を防ぐためスキップ
                if !didComplete, let self {
                    if let fallback = lastText, !didPostToChannel {
                        await self.postToChannel(fallback)
                    }
                    await self.yieldStep(.turnEnded)
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
