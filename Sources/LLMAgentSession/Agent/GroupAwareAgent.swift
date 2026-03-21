import Foundation
import AgentCommunication

/// グループ対応の LLM エージェントプロトコル
///
/// Workspace の組織構造を認識し、複数のグループチャンネルで同時に動作する
/// LLM ドメインのエージェント。
///
/// ## ChannelAgent との関係
///
/// `ChannelAgent` は単一チャンネル向けに設計されている。`GroupAwareAgent` は
/// 複数チャンネル対応が前提のため、`ChannelAgent` を継承せず独立したプロトコルとする。
///
/// 両プロトコルは同じプロパティ（`agentId`, `status`）を持つが、
/// 起動方法が異なる:
///
/// - `ChannelAgent.start(on channel:)` → 単一チャンネル
/// - `GroupAwareAgent.start(in workspace:)` → Workspace（複数チャンネル）
///
/// ## マイグレーションパス
///
/// 既存の `OrchestratorAgent` を GroupAwareAgent にマイグレーションする場合:
///
/// 1. 新しい `GroupOrchestratorAgent` を作成し、`GroupAwareAgent` に準拠させる
/// 2. 内部に既存の `ChatSessionProtocol` を保持
/// 3. `handleGroupMessage` で LLM ループを起動
/// 4. 既存の `OrchestratorAgent` は変更せず残す（後方互換性）
///
/// ## 使用例
///
/// ```swift
/// actor MyGroupAgent: GroupAwareAgent {
///     let agentId = "group-orchestrator"
///     private(set) var status: AgentStatus = .idle
///     private(set) var workspace: Workspace<String>?
///     let channelMerge = ChannelMerge<String>()
///
///     func handleGroupMessage(
///         _ message: AgentMessage<String>,
///         from channelId: String,
///         channelName: String
///     ) async {
///         // チャンネル出自を考慮した LLM ループ起動
///     }
///
///     func join(workspace: Workspace<String>) async {
///         self.workspace = workspace
///     }
/// }
///
/// // 起動
/// let agent = MyGroupAgent()
/// Task { await agent.start(in: workspace) }
/// ```
public protocol GroupAwareAgent: WorkspaceParticipant where Content == String {

    /// エージェントの一意識別子
    var agentId: String { get }

    /// エージェントの状態
    var status: AgentStatus { get }

    /// Workspace に参加してメッセージ受信を開始する
    ///
    /// 以下の処理を順に行う:
    /// 1. Workspace に join する
    /// 2. 所属グループのチャンネルに subscribe する
    /// 3. グローバルチャンネルに subscribe する
    /// 4. マージストリームでメッセージループを開始する
    ///
    /// - Important: このメソッドは `stop()` が呼ばれるか Task がキャンセルされるまで返りません。
    ///   `Task { await agent.start(in: workspace) }` で非同期に起動してください。
    func start(in workspace: Workspace<String>) async

    /// チャンネル出自付きメッセージを LLM ドメインで処理する
    ///
    /// `WorkspaceParticipant.handleOriginatedMessage` の LLM ドメイン版。
    /// チャンネル情報を個別のパラメータとして受け取ることで、
    /// LLM コンテキストに出自情報を注入しやすくする。
    func handleGroupMessage(
        _ message: AgentMessage<String>,
        from channelId: String,
        channelName: String
    ) async

    /// エージェントを停止する
    ///
    /// 全チャンネルの subscribe を解除し、メッセージループを終了する。
    func stop() async
}

// MARK: - Default Implementations

extension GroupAwareAgent {

    /// `participantId` のデフォルト実装
    ///
    /// `CommunicationParticipant.participantId` を `agentId` にマッピングする。
    public var participantId: String { agentId }

    /// `CommunicationParticipant.handleMessage` のデフォルト実装
    ///
    /// GroupAwareAgent のメッセージ処理は `handleGroupMessage` 経由で行われるため、
    /// このメソッドは通常 `runMerged()` 経由では呼ばれない。
    /// 直接 subscribe した場合のフォールバックとして、channelId 空文字列で
    /// `handleGroupMessage` に委譲する。
    public func handleMessage(_ message: AgentMessage<String>) async {
        await handleGroupMessage(message, from: "", channelName: "")
    }

    /// `handleOriginatedMessage` のデフォルト実装
    ///
    /// `OriginatedMessage` を分解して `handleGroupMessage` に委譲する。
    public func handleOriginatedMessage(_ message: OriginatedMessage<String>) async {
        await handleGroupMessage(
            message.message,
            from: message.origin.channelId.rawValue,
            channelName: message.origin.channelName
        )
    }

    /// `start(in:)` のデフォルト実装
    ///
    /// 所属グループとグローバルチャンネルに subscribe し、メッセージループを開始する。
    ///
    /// - Important: このメソッドは `stop()` が呼ばれるか Task がキャンセルされるまで返りません。
    ///   `Task { await agent.start(in: workspace) }` で非同期に起動してください。
    public func start(in workspace: Workspace<String>) async {
        await join(workspace: workspace)

        // 所属グループのチャンネルに subscribe
        let groups = await myGroups()
        for group in groups {
            await subscribeToGroupChannels(groupId: group.id)
        }

        // グローバルチャンネルに subscribe
        await subscribeToGlobalChannels()

        // マージストリームでメッセージループ開始
        await runMerged()
    }

    /// `stop()` のデフォルト実装
    public func stop() async {
        await leave()
    }
}
