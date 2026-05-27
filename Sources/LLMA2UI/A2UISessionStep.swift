import A2UICore
import LLMClient
import LLMTool

public enum A2UISessionStep: Sendable {
    /// LLM が思考中
    case thinking(LLMResponse)
    /// ツール呼び出し
    case toolCall(ToolCall)
    /// ツール実行結果
    case toolResult(ToolResponse)
    /// Surface が更新された（createSurface / updateComponents / updateDataModel / deleteSurface）
    case surfaceUpdated(String)
    /// 会話テキスト（A2UI ブロック外のテキスト部分）
    case text(String)
}
