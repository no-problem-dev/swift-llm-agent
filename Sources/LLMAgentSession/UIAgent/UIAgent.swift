import Foundation
import LLMClient
import AgentCommunication

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
/// ユーザー入力を最初に受信し、Orchestrator にタスクを委譲する。
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
/// Task { await uiAgent.run(on: channel) }
/// ```
public actor UIAgent: ChannelParticipant {
    public typealias Content = ChannelContent
    public typealias EventHandler = @Sendable (UIAgentEvent) async -> Void

    public let participantId: String = "uiAgent"

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

    // MARK: - ChannelParticipant

    /// チャンネルメッセージを処理する
    ///
    /// `ChannelParticipant` プロトコルの要件。
    /// `run(on:)` / `run(stream:)` はプロトコルのデフォルト実装を使用。
    public func handleMessage(_ message: ChannelMessage) async {
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
