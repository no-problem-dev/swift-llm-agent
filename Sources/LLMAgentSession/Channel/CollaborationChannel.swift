import Foundation
import AgentCommunication

// MARK: - Type Aliases

/// LLM ドメイン用の Pub/Sub チャンネル
///
/// `AgentCommunication.Channel<ChannelContent>` の typealias。
/// 汎用チャンネルに LLM 固有のメッセージ型を注入している。
public typealias CollaborationChannel = Channel<ChannelContent>

/// LLM ドメイン用のチャンネルメッセージ
///
/// `AgentCommunication.AgentMessage<ChannelContent>` の typealias。
public typealias ChannelMessage = AgentMessage<ChannelContent>

// MARK: - LLM Convenience Extensions

extension Channel where Content == ChannelContent {

    /// インタラクション応答を要求し、応答が返されるまで block する
    ///
    /// チャンネルに `.requestInteraction` を投稿し、対応する
    /// `.interactionResponse` が投稿されるまで待機する。
    public func requestInteraction(_ intent: InteractionIntent, from sender: String) async -> InteractionResponse {
        await request(
            id: intent.id,
            content: .requestInteraction(intent),
            from: sender,
            defaultResponse: InteractionResponse(requestId: "", content: .dismissed)
        )
    }

    /// ツール承認応答を要求し、応答が返されるまで block する
    public func requestAuthorization(_ approvalRequest: ToolApprovalRequest, from sender: String) async -> ToolApprovalResponse {
        await request(
            id: approvalRequest.id.uuidString,
            content: .requestAuthorization(approvalRequest),
            from: sender,
            defaultResponse: .deny
        )
    }

    /// 応答メッセージを処理（チャンネルに投稿 + pending continuation を resolve）
    ///
    /// `.interactionResponse` / `.authorizationResponse` は通常のメッセージとして
    /// チャンネルに投稿されつつ、対応する pending continuation も resolve する。
    public func postResponse(_ content: ChannelContent, from sender: String) {
        switch content {
        case .interactionResponse(let response, let requestId):
            respond(to: requestId, with: response, content: content, from: sender)
        case .authorizationResponse(let response, let requestId):
            respond(to: requestId, with: response, content: content, from: sender)
        default:
            post(content, from: sender)
        }
    }
}
