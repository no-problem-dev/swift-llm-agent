import Foundation
import LLMClient

// MARK: - SessionChannelContext

/// LLM ドメイン用のチャンネルコンテキスト
///
/// チャンネル参加者の目的と、各メンバーのロール定義（PromptComponent ベース）を保持する。
public struct SessionChannelContext: Sendable {
    /// グループの目的
    public let purpose: String

    /// メンバーごとのロール定義
    public let memberRoles: [String: [PromptComponent]]

    public init(purpose: String, memberRoles: [String: [PromptComponent]] = [:]) {
        self.purpose = purpose
        self.memberRoles = memberRoles
    }

    /// 特定メンバーのロールを取得
    public func role(for memberId: String) -> [PromptComponent]? {
        memberRoles[memberId]
    }

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
    public static var `default`: SessionChannelContext {
        SessionChannelContext(
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
