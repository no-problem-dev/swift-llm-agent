import Foundation
import LLMClient
import LLMTool

// MARK: - AskUserTool

/// インタラクティブモード用のテキスト入力ツール
///
/// `InteractiveTool` に準拠し、ユーザーに自由テキストで質問する。
/// セッションのランループがこのツールを検出すると、
/// `InteractionRequest(.textInput)` を生成して UI に suspend する。
@Tool(
    "Ask the user an open-ended question. " +
    "Use this tool when: (1) you need information that cannot be anticipated or enumerated, " +
    "(2) the user's request is ambiguous and you cannot proceed without clarification, " +
    "(3) you need free-form input like a topic, name, or description. " +
    "Do NOT use this tool when you can identify specific options — use ask_selection instead. " +
    "Do NOT write questions as plain text in your response — always use this tool.",
    name: "ask_user"
)
public struct AskUserTool {
    @ToolArgument("The question to ask the user. Be specific and clear about what information you need. Example: 'What topic would you like me to research?'")
    var question: String

    func call() async throws -> String {
        // セッション側で InteractiveTool として処理されるため、通常は呼び出されない
        return "Waiting for user response..."
    }
}

// MARK: - InteractiveTool Conformance

extension AskUserTool: InteractiveTool {
    public var interactionType: InteractionType { .textInput }

    public func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest {
        let question: String
        if let dict = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
           let q = dict["question"] as? String
        {
            question = q
        } else {
            question = "Please provide additional information."
        }

        return InteractionRequest(
            type: .textInput,
            prompt: question,
            payload: .textInput(placeholder: nil, multiline: false),
            dismissible: false
        )
    }

    public func makeToolResult(from response: InteractionResponse) -> ToolResult {
        let userText = response.content.textValue
        let result = """
        User responded: \(userText)

        IMPORTANT: Based on the user's response, decide your next action:
        - If you can now identify specific options or approaches → call ask_selection (DO NOT list options as text)
        - If you need to confirm a plan before executing → call ask_confirmation
        - If the task is now clear → proceed with execution using available tools
        - If you still need open-ended input → call ask_user again
        NEVER output questions, option lists, or choices as plain text.
        """
        return .text(result)
    }
}
