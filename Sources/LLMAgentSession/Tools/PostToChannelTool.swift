import Foundation
import LLMClient
import LLMTool
import AgentCommunication

// MARK: - PostToChannelTool

/// チャンネルにテキストを投稿するツール（非ブロッキング）
///
/// オーケストレーターが UIAgent やユーザーにメッセージを送るために使用する。
/// 投稿は即座に完了し、応答を待たない（fire-and-forget）。
public struct PostToChannelTool: Tool {
    public let toolName = "post_to_channel"
    public let toolDescription = "チャンネルにテキストメッセージを投稿します。UIAgent やユーザーへの連絡に使用してください。"
    public let inputSchema = JSONSchema.object(
        description: "post_to_channel arguments",
        properties: [
            "message": .string(description: "投稿するメッセージテキスト")
        ],
        required: ["message"]
    )

    private let channel: Channel<String>
    private let sender: String

    public init(channel: Channel<String>, sender: String = "orchestrator") {
        self.channel = channel
        self.sender = sender
    }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        struct Args: Decodable { let message: String }
        let args = try JSONDecoder().decode(Args.self, from: argumentsData)
        await channel.post(args.message, from: sender)
        return .text("Message posted to channel.")
    }
}
