import Foundation

// MARK: - SkillRegistry

/// スキルのレジストリ
///
/// 利用可能なスキルを管理します。
/// `SkillTool` のコンストラクタに渡して使用します。
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     AgentSkillDefinition(
///         name: "summarize",
///         description: "Summarizes text content",
///         executionMode: .inline,
///         instructions: "Create a concise summary..."
///     )
///     CodeReviewSkill()
/// }
///
/// registry.skill(named: "summarize") // AgentSkill?
/// registry.skillNames                // ["summarize", "code-review"]
/// ```
public protocol SkillRegistry: Sendable {
    /// 登録されたスキルの一覧
    var skills: [any AgentSkill] { get }
}

// MARK: - Default Implementation

extension SkillRegistry {
    /// 名前でスキルを検索
    public func skill(named name: String) -> (any AgentSkill)? {
        skills.first { $0.name == name }
    }

    /// 登録されたスキル名の一覧
    public var skillNames: [String] {
        skills.map(\.name)
    }

    /// LLM が呼び出し可能なスキルのみをフィルタ
    public var modelInvocableSkills: [any AgentSkill] {
        skills.filter(\.isModelInvocable)
    }

    /// ユーザーが呼び出し可能なスキルのみをフィルタ
    public var userInvocableSkills: [any AgentSkill] {
        skills.filter(\.isUserInvocable)
    }

    /// 常時有効なスキルのみをフィルタ
    public var requiredSkills: [any AgentSkill] {
        skills.filter { $0.availability == .required }
    }

    /// 任意有効なスキルのみをフィルタ
    public var optionalSkills: [any AgentSkill] {
        skills.filter { $0.availability == .optional }
    }
}

// MARK: - SkillRegistryDefinition

/// スキルレジストリの具象定義
///
/// Result Builder を使用して宣言的にレジストリを構築できます。
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     AgentSkillDefinition(
///         name: "summarize",
///         description: "Summarizes text",
///         executionMode: .inline,
///         instructions: "Create a concise summary..."
///     )
///     CodeReviewSkill()
/// }
/// ```
public struct SkillRegistryDefinition: SkillRegistry {
    public let skills: [any AgentSkill]

    /// Result Builder でレジストリを構築
    public init(@SkillRegistryBuilder _ builder: () -> [any AgentSkill]) {
        self.skills = builder()
    }

    /// 配列から直接初期化
    public init(skills: [any AgentSkill]) {
        self.skills = skills
    }
}

// MARK: - SkillRegistryBuilder

/// スキルレジストリ構築用の Result Builder
///
/// `SubAgentCatalogBuilder` と同じパターンで、条件分岐やループをサポートします。
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     AgentSkillDefinition(name: "a", description: "Skill A", instructions: "...")
///
///     if enableResearch {
///         ResearchSkill()
///     }
/// }
/// ```
@resultBuilder
public struct SkillRegistryBuilder {

    public static func buildBlock(_ skills: [any AgentSkill]...) -> [any AgentSkill] {
        skills.flatMap { $0 }
    }

    public static func buildExpression(_ skill: some AgentSkill) -> [any AgentSkill] {
        [skill]
    }

    public static func buildExpression(_ skills: [any AgentSkill]) -> [any AgentSkill] {
        skills
    }

    public static func buildExpression(_ kit: some SkillKit) -> [any AgentSkill] {
        kit.skills
    }

    public static func buildOptional(_ skills: [any AgentSkill]?) -> [any AgentSkill] {
        skills ?? []
    }

    public static func buildEither(first skills: [any AgentSkill]) -> [any AgentSkill] {
        skills
    }

    public static func buildEither(second skills: [any AgentSkill]) -> [any AgentSkill] {
        skills
    }

    public static func buildArray(_ skills: [[any AgentSkill]]) -> [any AgentSkill] {
        skills.flatMap { $0 }
    }

    public static func buildFinalResult(_ skills: [any AgentSkill]) -> [any AgentSkill] {
        skills
    }

    public static func buildLimitedAvailability(_ skills: [any AgentSkill]) -> [any AgentSkill] {
        skills
    }
}
