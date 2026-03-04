import Foundation
import LLMClient

// MARK: - ChannelContext

/// チャンネル用のコンテキスト（システムプロンプト + メンバーロール定義）
///
/// チャンネルの目的と各メンバーの役割を定義する。
/// Orchestrator / UIAgent のシステムプロンプトに注入して、
/// チャンネル上でのコラボレーションを自然にする。
public struct ChannelContext: Sendable {
    /// チャンネルの目的
    public let purpose: String
    /// メンバーごとのロールプロンプト
    public let memberRoles: [String: [PromptComponent]]

    public init(
        purpose: String,
        memberRoles: [String: [PromptComponent]]
    ) {
        self.purpose = purpose
        self.memberRoles = memberRoles
    }

    /// 特定メンバー用のプロンプトコンポーネントを返す
    public func promptComponents(for memberId: String) -> [PromptComponent] {
        var components: [PromptComponent] = [
            .context("Collaboration channel: \(purpose)")
        ]
        if let roleComponents = memberRoles[memberId] {
            components.append(contentsOf: roleComponents)
        }
        return components
    }

    /// デフォルトのチャンネルコンテキスト
    public static let `default` = ChannelContext(
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
