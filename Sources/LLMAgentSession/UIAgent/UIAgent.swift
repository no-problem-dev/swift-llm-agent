import Foundation
import LLMClient

// MARK: - UIAgent

/// UI 関心事を一元管理するエージェント（エントリーポイント）
///
/// CollaborationChannel の subscriber として動作し、以下を担当する:
/// - ユーザー入力の受信と初期ブロック表示
/// - Orchestrator への委譲要求
/// - エージェントステップのパススルー
/// - インタラクション要求の中継
/// - ツール承認要求の中継
/// - ターン完了時の UI 生成起動
///
/// ## 設計
///
/// UIAgent はセッションのエントリーポイントとして機能する。
/// ユーザー入力を最初に受信し、即座に初期 UI ブロックを emit してから
/// Orchestrator にタスクを委譲する。
/// Orchestrator の結果は Channel 経由で UIAgent に返され、
/// UIAgent が UI ブロック生成を制御する。
///
/// UIAgent は LLM を直接保持しない。UI ブロック生成・画像配置・画像生成は
/// 型消去されたクロージャ（Runner）経由で実行する。
///
/// ## 使い方
///
/// ```swift
/// let uiAgent = UIAgent(eventHandler: { event in
///     await MainActor.run { sessionAgent.handleUIAgentEvent(event) }
/// })
///
/// // Channel 上で起動
/// Task { await uiAgent.run(channel: channel) }
/// ```
public actor UIAgent {
    public typealias EventHandler = @Sendable (UIAgentEvent) async -> Void

    private var eventHandler: EventHandler

    // MARK: - Initialization

    public init(
        eventHandler: @escaping EventHandler = { _ in }
    ) {
        self.eventHandler = eventHandler
    }

    /// イベントハンドラーを更新
    ///
    /// SessionAgent の init 時点では `self` のキャプチャが不可能なため、
    /// UIAgent 起動前にハンドラーを設定する。
    public func setEventHandler(_ handler: @escaping EventHandler) {
        self.eventHandler = handler
    }

    // MARK: - Main Loop

    /// Channel からのメッセージを処理するメインループ
    ///
    /// Channel の subscribe で取得した AsyncStream を for-await で消費する。
    /// Channel が close されるか Task がキャンセルされると終了する。
    public func run(channel: CollaborationChannel) async {
        let stream = await channel.subscribe(as: "uiAgent")
        await run(stream: stream)
    }

    /// 事前取得済みの AsyncStream を消費するメインループ
    ///
    /// subscribe を呼び出し側で先に行い、確実にメッセージを受信できるようにする場合に使用。
    public func run(stream: AsyncStream<ChannelMessage>) async {
        for await message in stream {
            guard !Task.isCancelled else { break }
            await handleMessage(message)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: ChannelMessage) async {
        switch message.content {
        case .userInput(let input):
            // UIAgent がエントリーポイント: 入力を受け取り、UI に通知後 Orchestrator を起動要求
            await eventHandler(.inputReceived(input))
            await eventHandler(.orchestrationRequested(input))

        case .step(let step):
            await eventHandler(.step(step))

        case .contentReady(let intent):
            // コンテンツ到着を通知（SessionAgent 側で UI 生成を起動）
            await eventHandler(.generationStarted(rawText: intent.content))

        case .requestInteraction(let intent):
            await eventHandler(.interactionRequested(intent))

        case .requestAuthorization(let request):
            await eventHandler(.authorizationRequested(request))

        case .turnCompleted(let result):
            await eventHandler(.turnCompleted(result))

        case .turnFailed(let error):
            await eventHandler(.turnFailed(error))

        case .sessionCancelled:
            await eventHandler(.sessionCancelled)

        case .userAction, .interactionResponse, .authorizationResponse:
            // UIAgent は応答メッセージを処理しない（Orchestrator 側で処理）
            break
        }
    }
}
