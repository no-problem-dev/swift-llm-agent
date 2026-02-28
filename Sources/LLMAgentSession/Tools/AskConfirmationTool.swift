import Foundation
import LLMClient
import LLMTool

// MARK: - AskConfirmationTool

/// インタラクティブモード用の承認ツール
///
/// `InteractiveTool` に準拠し、ユーザーに提案を承認/修正/却下させる。
/// セッションのランループがこのツールを検出すると、
/// `InteractionRequest(.confirmation)` を生成して UI に suspend する。
@Tool(
    "Present a proposal for the user to approve, modify, or reject. " +
    "Use this tool when: (1) you have a specific plan or action to confirm before executing, " +
    "(2) the action has significant consequences or is irreversible, " +
    "(3) you want to give the user a chance to refine your approach. " +
    "Do NOT ask for confirmation as plain text — always use this tool.",
    name: "ask_confirmation"
)
public struct AskConfirmationTool {
    @ToolArgument("The proposal or plan to present for confirmation. Be specific about what you intend to do.")
    var proposal: String

    @ToolArgument("Whether the user can modify the proposal text. Defaults to true.")
    var allowModification: Bool

    func call() async throws -> String {
        // セッション側で InteractiveTool として処理されるため、通常は呼び出されない
        return "Waiting for user confirmation..."
    }
}

// MARK: - InteractiveTool Conformance

extension AskConfirmationTool: InteractiveTool {
    public var interactionType: InteractionType { .confirmation }

    public func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest {
        let proposal: String
        let allowModification: Bool

        if let dict = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any] {
            proposal = (dict["proposal"] as? String) ?? "Please confirm."
            allowModification = (dict["allow_modification"] as? Bool) ?? true
        } else {
            proposal = "Please confirm."
            allowModification = true
        }

        return InteractionRequest(
            type: .confirmation,
            prompt: proposal,
            payload: .confirmation(proposal: proposal, allowModification: allowModification),
            dismissible: false
        )
    }

    public func makeToolResult(from response: InteractionResponse) -> ToolResult {
        let userText = response.content.textValue
        let result = """
        User responded to confirmation: \(userText)

        Act on the user's decision. If you need further input, use the appropriate interaction tool (ask_selection, ask_user, or ask_confirmation). NEVER output questions or choices as plain text.
        """
        return .text(result)
    }
}
