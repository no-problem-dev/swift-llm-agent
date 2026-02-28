import Foundation

// MARK: - ModelTier

/// モデルの強度レベルを表す抽象ティア
///
/// プロバイダーに依存せず、サブエージェントやスキルが要求する
/// モデルの「強さ」を指定します。各プロバイダーは `ModelTierResolver`
/// クロージャを通じてこれを具体的なモデルにマッピングします。
///
/// ## 使用例
///
/// ```swift
/// // サブエージェント定義
/// SubAgentTypeDefinition(
///     name: "writer",
///     description: "Text generation",
///     tools: ToolSet {},
///     modelTier: .light  // 軽量モデルで十分
/// )
///
/// // プロバイダー側のリゾルバー
/// let resolver: ModelTierResolver<AnthropicModel> = { tier in
///     switch tier {
///     case .light: return .haiku
///     case .standard: return .sonnet
///     case .powerful: return .opus
///     }
/// }
/// ```
public enum ModelTier: Int, Sendable, Codable, Comparable, CaseIterable {
    /// 軽量・高速・低コスト（例: Haiku, GPT-4o-mini, Gemini Flash）
    case light = 1

    /// 標準・バランス型（例: Sonnet, GPT-4o, Gemini Pro）
    case standard = 2

    /// 高性能・高コスト（例: Opus, o1, Gemini Ultra）
    case powerful = 3

    public static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ModelTierResolver

/// モデルティアを具体的なモデルに解決するクロージャ
///
/// 各プロバイダーの設定時に提供し、`DelegateTaskTool` や `SkillTool` に渡します。
///
/// ```swift
/// let resolver: ModelTierResolver<AnthropicModel> = { tier in
///     switch tier {
///     case .light: return .haiku
///     case .standard: return .sonnet35_v2
///     case .powerful: return .opus4
///     }
/// }
/// ```
public typealias ModelTierResolver<Model: Sendable> = @Sendable (ModelTier) -> Model
