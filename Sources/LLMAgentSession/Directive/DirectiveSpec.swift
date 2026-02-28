import Foundation
import LLMClient

// MARK: - DirectiveSpec

/// AI 駆動ディレクティブ生成用の Structured Output 型
///
/// 隔離コンテキストで LLM を呼び出し、出力結果に基づいた
/// 動的なインタラクション提案を生成する際に使用する。
///
/// ## 将来の実装イメージ
///
/// ```swift
/// struct AIDirectiveGenerator: DirectiveGenerator {
///     let client: any AgentCapableClient
///
///     func generate(from result: StructuredResult) async throws -> InteractionRequest? {
///         let spec: DirectiveSpec = try await client.generate(
///             prompt: "Generate directive for: \(result.markdown)",
///             outputType: DirectiveSpec.self
///         )
///         return spec.toInteractionRequest()
///     }
/// }
/// ```
@Structured("Directive specification for next user interaction")
public struct DirectiveSpec {
    @StructuredField("The prompt to show the user")
    public var prompt: String

    @StructuredField("Action buttons for the user to choose from")
    public var actions: [DirectiveSpecAction]

    @StructuredField("Quick reply suggestions")
    public var quickReplies: [DirectiveSpecQuickReply]

    @StructuredField("Whether the user can dismiss the directive")
    public var dismissible: Bool
}

/// AI 生成ディレクティブのアクション定義
@Structured("An action button in the directive")
public struct DirectiveSpecAction {
    @StructuredField("Display label for the action")
    public var label: String

    @StructuredField("SF Symbol icon name")
    public var icon: String

    @StructuredField("Style: primary, standard, or destructive")
    public var style: String

    @StructuredField("Message to send when this action is selected")
    public var message: String
}

/// AI 生成ディレクティブのクイックリプライ定義
@Structured("A quick reply suggestion")
public struct DirectiveSpecQuickReply {
    @StructuredField("Display label for the quick reply")
    public var label: String

    @StructuredField("SF Symbol icon name")
    public var icon: String

    @StructuredField("Message to send when this quick reply is selected")
    public var message: String
}

// MARK: - Conversion

extension DirectiveSpec {
    /// DirectiveSpec を InteractionRequest に変換
    public func toInteractionRequest() -> InteractionRequest {
        let actionOptions = actions.map { action in
            ActionOption(
                label: action.label,
                icon: action.icon,
                style: ActionOption.ActionStyle(rawValue: action.style) ?? .standard,
                message: action.message
            )
        }

        let quickReplyOptions = quickReplies.map { reply in
            QuickReplyOption(
                label: reply.label,
                icon: reply.icon,
                message: reply.message
            )
        }

        return InteractionRequest(
            type: .actionMenu,
            prompt: prompt,
            payload: .actionMenu(actions: actionOptions, quickReplies: quickReplyOptions),
            dismissible: dismissible
        )
    }
}
