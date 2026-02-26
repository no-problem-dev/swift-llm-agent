import Foundation

// MARK: - SkillExecutionMode

/// スキルの実行モード
///
/// Agent Skills 標準に準拠した実行モードです。
/// - `inline`: 指示をツール結果として返し、エージェントが後続ステップで従う
/// - `fork`: サブエージェントを起動し、指示をシステムプロンプトとして委譲
public enum SkillExecutionMode: String, Sendable, Codable, Equatable {
    /// 指示をツール結果として親エージェントのコンテキストに注入
    case inline
    /// サブエージェントに委譲して独立実行
    case fork
}
