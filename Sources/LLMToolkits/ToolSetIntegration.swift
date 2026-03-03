import LLMTool
import LLMMCP
import LLMA2A

extension ToolSet {
    /// MCP + A2A の全プレースホルダーを一括解決
    public func resolvingAllPlaceholders() async throws -> ToolSet {
        var result = self
        if result.containsMCPPlaceholders {
            result = try await result.resolvingMCPServers()
        }
        if result.containsA2APlaceholders {
            result = try await result.resolvingA2AAgents()
        }
        return result
    }

    /// いずれかのプレースホルダーが含まれているか
    public var containsPlaceholders: Bool {
        containsMCPPlaceholders || containsA2APlaceholders
    }
}
