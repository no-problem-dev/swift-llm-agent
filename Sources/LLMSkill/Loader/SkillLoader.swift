import Foundation
import StructuredDataCore
import LLMAgent

// MARK: - SkillLoader

/// SKILL.md ファイルからスキルを読み込むローダー
///
/// Agent Skills 標準の SKILL.md 形式（YAML フロントマター + Markdown 本文）を
/// パースし、`AgentSkillDefinition` に変換します。
///
/// ## SKILL.md 形式
///
/// ```markdown
/// ---
/// name: code-review
/// description: Reviews code for quality and best practices
/// context: fork
/// allowed-tools:
///   - read_file
///   - search_code
/// ---
///
/// # Code Review Instructions
///
/// When reviewing code, check for:
/// 1. Correctness
/// 2. Security
/// ```
///
/// ## 使用例
///
/// ```swift
/// // ディレクトリから全スキルを読み込み
/// let skills = try SkillLoader.loadSkills(from: skillsDirectory)
///
/// // 単一ファイルを読み込み
/// let skill = try SkillLoader.loadSkill(from: skillFileURL)
///
/// // 文字列からパース
/// let skill = try SkillLoader.parse(content: markdownString)
/// ```
public enum SkillLoader {

    /// ディレクトリ内の全 SKILL.md ファイルを読み込み
    ///
    /// 指定ディレクトリ直下とサブディレクトリの `SKILL.md` ファイルを
    /// 再帰的に検索して読み込みます。
    ///
    /// - Parameter directory: 検索するディレクトリの URL
    /// - Returns: 読み込まれたスキルの配列
    /// - Throws: ファイル読み込みまたはパースエラー
    public static func loadSkills(from directory: URL) throws -> [AgentSkillDefinition] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var skills: [AgentSkillDefinition] = []

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "SKILL.md" {
                do {
                    let skill = try loadSkill(from: fileURL)
                    skills.append(skill)
                } catch {
                    throw SkillError.fileLoadError(fileURL, error)
                }
            }
        }

        return skills
    }

    /// 単一の SKILL.md ファイルを読み込み
    ///
    /// - Parameter file: SKILL.md ファイルの URL
    /// - Returns: パースされたスキル定義
    /// - Throws: ファイル読み込みまたはパースエラー
    public static func loadSkill(from file: URL) throws -> AgentSkillDefinition {
        let content: String
        do {
            content = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw SkillError.fileLoadError(file, error)
        }
        return try parse(content: content)
    }

    /// SKILL.md 形式の文字列をパース
    ///
    /// - Parameter content: YAML フロントマター + Markdown 本文
    /// - Returns: パースされたスキル定義
    /// - Throws: パースエラー
    public static func parse(content: String) throws -> AgentSkillDefinition {
        let frontmatter: StructuredValue
        let body: String
        do {
            (frontmatter, body) = try FrontmatterParser.parse(content)
        } catch let error as FrontmatterParseError {
            throw SkillError.parseError(error.localizedDescription)
        }

        let fields: Fields
        do {
            fields = try frontmatter.decode(Fields.self)
        } catch {
            throw SkillError.parseError("Invalid SKILL.md frontmatter: \(error)")
        }

        // 必須フィールド
        guard let name = fields.name else {
            throw SkillError.missingRequiredField("name")
        }
        guard let description = fields.description else {
            throw SkillError.missingRequiredField("description")
        }

        // 実行モード（context フィールド）
        let executionMode: SkillExecutionMode
        if let contextStr = fields.context {
            guard let mode = SkillExecutionMode(rawValue: contextStr) else {
                throw SkillError.invalidExecutionMode(contextStr)
            }
            executionMode = mode
        } else {
            executionMode = .inline
        }

        // fork スキルには allowed-tools を必須化
        if executionMode == .fork && fields.allowedTools == nil {
            throw SkillError.missingAllowedToolsForFork(name)
        }

        // 利用可能性
        let availability: SkillAvailability
        if let availStr = fields.availability {
            guard let parsed = SkillAvailability(rawValue: availStr) else {
                throw SkillError.invalidAvailability(availStr)
            }
            availability = parsed
        } else {
            availability = .required
        }

        // 呼び出し制御
        let isUserInvocable = fields.userInvocable ?? true
        let disableModel = fields.disableModelInvocation ?? false
        let invocationMode: SkillInvocationMode
        if isUserInvocable && !disableModel {
            invocationMode = .both
        } else if isUserInvocable && disableModel {
            invocationMode = .userOnly
        } else if !isUserInvocable && !disableModel {
            invocationMode = .modelOnly
        } else {
            // Neither user nor model invocable
            invocationMode = .none
        }

        var metadata: SkillMetadata? = nil
        if fields.license != nil || fields.compatibility != nil || fields.version != nil
            || fields.author != nil || fields.tags != nil {
            metadata = SkillMetadata(
                license: fields.license,
                compatibility: fields.compatibility,
                version: fields.version,
                author: fields.author,
                tags: fields.tags
            )
        }

        // AgentConfiguration（maxSteps をフロントマターから読む）
        var configuration = AgentConfiguration.default
        if let maxSteps = fields.maxSteps {
            configuration = AgentConfiguration(maxSteps: maxSteps)
        }

        // モデルティア（整数 or light/standard/powerful の文字列）
        let modelTier: ModelTier
        if let spec = fields.modelTier {
            guard let resolved = spec.resolved else {
                throw SkillError.invalidModelTier(spec.description)
            }
            modelTier = resolved
        } else {
            modelTier = .standard
        }

        // 本文（instructions）
        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            throw SkillError.parseError("SKILL.md body (instructions) is empty")
        }

        return AgentSkillDefinition(
            name: name,
            description: description,
            executionMode: executionMode,
            instructions: instructions,
            allowedTools: fields.allowedTools,
            configuration: configuration,
            availability: availability,
            displayName: fields.displayName,
            iconName: fields.icon ?? "sparkles",
            category: fields.category,
            displayOrder: fields.displayOrder ?? 999,
            invocationMode: invocationMode,
            argumentHint: fields.argumentHint,
            metadata: metadata,
            modelTier: modelTier,
            isEphemeral: fields.ephemeral ?? false
        )
    }

    /// SKILL.md フロントマターの型付き表現。文字列キーは ``CodingKeys`` の一箇所に封じ込め、
    /// ロジックは型安全なプロパティ参照のみで扱う。
    private struct Fields: Decodable {
        let name: String?
        let description: String?
        let context: String?
        let allowedTools: [String]?
        let displayName: String?
        let icon: String?
        let category: String?
        let displayOrder: Int?
        let availability: String?
        let userInvocable: Bool?
        let disableModelInvocation: Bool?
        let argumentHint: String?
        let ephemeral: Bool?
        let license: String?
        let compatibility: String?
        let version: String?
        let author: String?
        let tags: [String]?
        let maxSteps: Int?
        let modelTier: ModelTier.Spec?

        enum CodingKeys: String, CodingKey {
            case name, description, context, icon, category, availability, ephemeral
            case license, compatibility, version, author, tags
            case allowedTools = "allowed-tools"
            case displayName = "display-name"
            case displayOrder = "display-order"
            case userInvocable = "user-invocable"
            case disableModelInvocation = "disable-model-invocation"
            case argumentHint = "argument-hint"
            case maxSteps = "max-steps"
            case modelTier = "model-tier"
        }
    }
}
