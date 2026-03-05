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
public protocol ChannelAgent: Actor {
    var agentId: String { get }
    var status: AgentStatus { get }

    /// チャンネル上でエージェントを起動
    func start(on channel: Channel<String>) async

    /// エージェントを停止
    func stop() async
}
