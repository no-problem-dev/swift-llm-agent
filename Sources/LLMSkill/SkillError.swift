import Foundation

// MARK: - SkillError

/// スキル実行固有のエラー
public enum SkillError: Error, Sendable {
    /// スキルが見つからない
    case skillNotFound(String)

    /// SKILL.md のパース失敗
    case parseError(String)

    /// フロントマターに必須フィールドがない
    case missingRequiredField(String)

    /// 無効な実行モード
    case invalidExecutionMode(String)

    /// ファイル読み込みエラー
    case fileLoadError(URL, any Error)
}

// MARK: - LocalizedError

extension SkillError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .skillNotFound(let name):
            "Skill not found: \"\(name)\""
        case .parseError(let detail):
            "Failed to parse SKILL.md: \(detail)"
        case .missingRequiredField(let field):
            "Missing required field in SKILL.md: \(field)"
        case .invalidExecutionMode(let mode):
            "Invalid execution mode: \"\(mode)\". Use \"inline\" or \"fork\""
        case .fileLoadError(let url, let error):
            "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
