import Foundation
import LLMClient
import LLMTool

// MARK: - RequestUserInputTool

/// 統合ユーザー入力ツール
///
/// Orchestrator が持つ唯一のインタラクションツール。
/// ユーザーに必要な情報を説明し、オプションで UI タイプをヒントとして指定する。
/// 実際の UI 表現（テキスト入力、選択リスト、日付ピッカー等）は
/// UIAgent / SessionAgent が `UserInputPayload.typeHint` を基に自動判断する。
///
/// ## 使用例（LLM 側）
///
/// ```json
/// {"name": "request_user_input", "input": {
///   "description": "どの料理ジャンルが好みですか？",
///   "type": "selection",
///   "options": ["和食", "洋食", "中華", "イタリアン"]
/// }}
/// ```
@Tool(
    "Request input from the user. Describe what information you need. " +
    "The system will present the appropriate UI (text input, selection, date picker, etc.). " +
    "Use this whenever you need any information or decision from the user.",
    name: "request_user_input"
)
public struct RequestUserInputTool {
    @ToolArgument("Clear description of what you need from the user")
    var description: String

    @ToolArgument("Optional UI hint: 'text', 'selection', 'confirmation', 'date', 'photo', 'location'")
    var type: String?

    @ToolArgument("Options to present (for selection-type requests)")
    var options: [String]?

    func call() async throws -> String {
        // セッション側で InteractiveTool として処理されるため、通常は呼び出されない
        return "Waiting for user input..."
    }
}

// MARK: - InteractiveTool Conformance

extension RequestUserInputTool: InteractiveTool {
    public func makeInteractionRequest(from arguments: Data) throws -> InteractionRequest {
        let dict = (try? JSONSerialization.jsonObject(with: arguments) as? [String: Any]) ?? [:]
        let desc = (dict["description"] as? String) ?? "Please provide input."
        let typeHint = dict["type"] as? String
        let options = dict["options"] as? [String]

        return InteractionRequest(
            prompt: desc,
            payload: InteractionPayload(UserInputPayload(
                description: desc, typeHint: typeHint, options: options
            )),
            dismissible: false
        )
    }

    public func makeToolResult(from response: InteractionResponse) -> ToolResult {
        .text(response.content.textValue)
    }
}
