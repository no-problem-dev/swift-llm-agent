import A2UICore
import LLMClient
import LLMTool

public enum A2UISessionStep: Sendable {
    case thinking(LLMResponse)
    case toolCall(ToolCall)
    case toolResult(ToolResponse)
    case surfaceUpdated(String)
    case text(String)
    case decodeEvent(A2UIDecodeEvent)
}
