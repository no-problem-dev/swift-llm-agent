import A2UICore
import A2UIParser
import LLMClient
import LLMTool

public enum A2UIAgentStep: Sendable {
    case thinking(LLMResponse)
    case toolCall(ToolCall)
    case toolResult(ToolResponse)
    case responsePart(A2UIResponsePart)
}
