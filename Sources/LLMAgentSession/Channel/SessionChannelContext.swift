import Foundation
import LLMClient
import AgentCommunication

// MARK: - SessionChannelContext

/// LLM ドメイン用のチャンネルコンテキスト
public typealias SessionChannelContext = CommunicationContext<[PromptComponent]>

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
                    ユーザーに直接質問する場合は post_to_channel ツールを使い、
                    UIAgent に質問を依頼してください。
                    タスク完了時は結果サマリーをチャンネルに投稿してください。
                    """)
                ],
                "uiAgent": [
                    .instruction("""
                    あなたは UI 表示とユーザー対話を担当するエージェントです。
                    チャンネルのメッセージを監視し、オーケストレーターからの依頼に応じて
                    UI ブロックを生成したり、ユーザーにインタラクションを要求してください。
                    ユーザーの回答はチャンネルに投稿してオーケストレーターに伝えてください。
                    """)
                ]
            ]
        )
    }
}
