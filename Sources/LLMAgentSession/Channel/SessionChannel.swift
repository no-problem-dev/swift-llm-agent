import Foundation
import AgentCommunication

// MARK: - Type Aliases

/// LLM ドメイン用の Pub/Sub チャンネル
///
/// チャンネルメッセージはただの文字列。
/// 大きなデータは共有ワークスペースにファイルとして書き出し、
/// チャンネルにはパスを伝えるだけ。
public typealias SessionChannel = Channel<String>
