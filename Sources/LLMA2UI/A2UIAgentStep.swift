import A2UICore
import A2UIParser
import LLMClient
import LLMTool

public enum A2UIAgentStep: Sendable {
    case thinking(LLMResponse)
    case toolCall(ToolCall)
    case toolResult(ToolResponse)
    case responsePart(A2UIResponsePart)
    /// Emitted around each decode attempt and retry so hosts can show parse activity in debug UIs.
    case decodeEvent(A2UIDecodeEvent)
    /// Emitted once at the end of a turn with the full conversation history (including tool use /
    /// tool result blocks) that should be reused as `initialMessages` of the next turn.
    case turnCompleted(messages: [LLMMessage])
}
