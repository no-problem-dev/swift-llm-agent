import Foundation

// MARK: - SubAgentLoaderError

/// AGENT.md のロード・パース時のエラー
public enum SubAgentLoaderError: Error, Sendable {
    /// フロントマターに必須フィールドがない
    case missingRequiredField(String)
    /// 無効なモデルティア値
    case invalidModelTier(String)
    /// allowed-tools が指定されていない
    case missingAllowedTools(String)
    /// 本文（instructions / systemPrompt）が空
    case emptyInstructions
    /// ファイル読み込みエラー
    case fileLoadError(URL, any Error)
}

// MARK: - LocalizedError

extension SubAgentLoaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            "Missing required field in AGENT.md: \(field)"
        case .invalidModelTier(let value):
            "Invalid model-tier: \"\(value)\". Use 1/2/3 or light/standard/powerful"
        case .missingAllowedTools(let name):
            "Agent \"\(name)\" must specify allowed-tools"
        case .emptyInstructions:
            "AGENT.md body (system prompt) is empty"
        case .fileLoadError(let url, let error):
            "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
