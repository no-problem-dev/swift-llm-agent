import Foundation
import LLMClient
import LLMTool

// MARK: - AskSelectionTool

/// インタラクティブモード用の選択式ツール
///
/// `InteractiveTool` に準拠し、ユーザーに選択肢を提示する。
/// セッションのランループがこのツールを検出すると、
/// `InteractionRequest(.selection)` を生成して UI に suspend する。
@Tool(
    "Present a list of options for the user to select from. " +
    "Use this tool when: (1) you can identify 2-10 specific alternatives, " +
    "(2) the user asks for suggestions or choices, " +
    "(3) multiple valid approaches exist and the user should decide. " +
    "ALWAYS prefer this over ask_user when the choices are enumerable. " +
    "Do NOT list options as plain text in your response — always use this tool to present choices.",
    name: "ask_selection"
)
public struct AskSelectionTool {
    @ToolArgument("The question explaining what the user should choose. Example: 'Which topic interests you most?'")
    var question: String

    @ToolArgument("The list of option labels to present (2-10 options). Example: ['AI trends', 'Climate change', 'Space exploration']")
    var options: [String]

    @ToolArgument("Whether the user can select multiple options. Defaults to false.")
    var allowMultiple: Bool

    func call() async throws -> String {
        // セッション側で InteractiveTool として処理されるため、通常は呼び出されない
        return "Waiting for user selection..."
    }
}

// MARK: - InteractiveTool Conformance

extension AskSelectionTool: InteractiveTool {
    public var interactionType: InteractionType { .selection }

    public func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest {
        let question: String
        let optionLabels: [String]
        let allowMultiple: Bool

        if let dict = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any] {
            question = (dict["question"] as? String) ?? "Please select an option."
            optionLabels = (dict["options"] as? [String]) ?? []
            allowMultiple = (dict["allow_multiple"] as? Bool) ?? false
        } else {
            question = "Please select an option."
            optionLabels = []
            allowMultiple = false
        }

        let selectionOptions = optionLabels.map { label in
            SelectionOption(id: label, label: label)
        }

        return InteractionRequest(
            type: .selection,
            prompt: question,
            payload: .selection(options: selectionOptions, allowMultiple: allowMultiple),
            dismissible: false
        )
    }

    public func makeToolResult(from response: InteractionResponse) -> ToolResult {
        let userText = response.content.textValue
        let result = """
        User selected: \(userText)

        Proceed with the user's selection. If you need further input, use the appropriate interaction tool (ask_selection, ask_user, or ask_confirmation). NEVER output questions or choices as plain text.
        """
        return .text(result)
    }
}
