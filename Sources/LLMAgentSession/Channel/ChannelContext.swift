import Foundation
import LLMClient
import AgentCommunication

// MARK: - ChannelContext

/// LLM ドメイン用のチャンネルコンテキスト
///
/// `CommunicationContext<[PromptComponent]>` の typealias。
/// 汎用コンテキストに LLM 固有の PromptComponent ベースのロール定義を注入。
public typealias ChannelContext = CommunicationContext<[PromptComponent]>

// MARK: - LLM Extensions

extension CommunicationContext where Role == [PromptComponent] {

    /// 特定メンバー用のプロンプトコンポーネントを返す
    public func promptComponents(for memberId: String) -> [PromptComponent] {
        var components: [PromptComponent] = [
            .context("Collaboration channel: \(purpose)")
        ]
        if let roleComponents = role(for: memberId) {
            components.append(contentsOf: roleComponents)
        }
        return components
    }

    /// デフォルトのチャンネルコンテキスト
    public static var `default`: CommunicationContext<[PromptComponent]> {
        CommunicationContext(
            purpose: "Task collaboration between user, orchestrator, and UI agent",
            memberRoles: [
                "orchestrator": [
                    .instruction("""
                    あなたはタスク実行を担当するオーケストレーターです。
                    共同チャンネルに UIAgent とユーザーが参加しています。
                    作業の進捗は自然にステップとして共有されます。
                    タスク完了時は結果サマリーを返してください。
                    """)
                ],
                "uiAgent": [
                    .instruction("""
                    あなたは UI 表示を担当するエージェントです。
                    チャンネルのメッセージを監視し、ユーザー入力には即座に応答します。
                    オーケストレーターの完了報告を受けたら、UI ブロックを生成してください。
                    """)
                ]
            ]
        )
    }
}
