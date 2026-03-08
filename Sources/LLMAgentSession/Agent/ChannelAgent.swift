import Foundation
import AgentCommunication

// MARK: - AgentStatus

/// チャンネルエージェントの状態
public enum AgentStatus: Sendable {
    case idle
    /// 購読中、メッセージ待ち
    case listening
    /// LLM ループ実行中
    case processing
    case stopped
}

// MARK: - ChannelAgent

/// チャンネルベースのエージェントプロトコル
///
/// `Channel<String>` を購読し、メッセージをトリガーに LLM ループを実行する。
/// オーケストレーターと UIAgent の共通インターフェース。
///
/// ## 起動パターン
///
/// ### 自律起動（エージェント自身が subscribe）
/// ```swift
/// await agent.start(on: channel)
/// ```
///
/// ### 事前 subscribe（呼び出し側がタイミングを制御）
/// ```swift
/// let stream = await channel.subscribe(as: agent.agentId)
/// Task { await agent.listen(on: channel, messages: stream) }
/// ```
///
/// 事前 subscribe パターンでは、subscribe 完了後にメッセージを post すれば
/// 確実にエージェントが受信できる（レースコンディション回避）。
public protocol ChannelAgent: Actor {
    var agentId: String { get }
    var status: AgentStatus { get }

    /// チャンネル上でエージェントを起動（自身で subscribe する）
    func start(on channel: Channel<String>) async

    /// 事前に subscribe 済みのストリームでメッセージ待受を開始
    ///
    /// 呼び出し側が `channel.subscribe(as: agentId)` を await した後に
    /// このメソッドを呼ぶことで、subscribe 完了とメッセージ post の
    /// 順序を保証できる。
    func listen(on channel: Channel<String>, messages: AsyncStream<AgentMessage<String>>) async

    /// エージェントを停止
    func stop() async
}
