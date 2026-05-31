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

        // 必須フィールド
        guard let name = frontmatter.string("name") else {
            throw SkillError.missingRequiredField("name")
        }
        guard let description = frontmatter.string("description") else {
            throw SkillError.missingRequiredField("description")
        }

        // 実行モード（context フィールド）
        let executionMode: SkillExecutionMode
        if let contextStr = frontmatter.string("context") {
            guard let mode = SkillExecutionMode(rawValue: contextStr) else {
                throw SkillError.invalidExecutionMode(contextStr)
            }
            executionMode = mode
        } else {
            executionMode = .inline
        }

        // 許可ツール
        let allowedTools = frontmatter.stringArray("allowed-tools")

        // fork スキルには allowed-tools を必須化
        if executionMode == .fork && allowedTools == nil {
            throw SkillError.missingAllowedToolsForFork(name)
        }

        // 表示メタデータ
        let displayName = frontmatter.string("display-name")
        let iconName = frontmatter.string("icon") ?? "sparkles"
        let category = frontmatter.string("category")
        let displayOrder = frontmatter.int("display-order") ?? 999

        // 利用可能性
        let availability: SkillAvailability
        if let availStr = frontmatter.string("availability") {
            guard let parsed = SkillAvailability(rawValue: availStr) else {
                throw SkillError.invalidAvailability(availStr)
            }
            availability = parsed
        } else {
            availability = .required
        }

        // 呼び出し制御
        let isUserInvocable = frontmatter.bool("user-invocable") ?? true
        let disableModel = frontmatter.bool("disable-model-invocation") ?? false
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

        let argumentHint = frontmatter.string("argument-hint")
        let isEphemeral = frontmatter.bool("ephemeral") ?? false

        // メタデータ
        let license = frontmatter.string("license")
        let compatibility = frontmatter.string("compatibility")
        let version = frontmatter.string("version")
        let author = frontmatter.string("author")
        let tags = frontmatter.stringArray("tags")

        var metadata: SkillMetadata? = nil
        if license != nil || compatibility != nil || version != nil || author != nil || tags != nil {
            metadata = SkillMetadata(
                license: license,
                compatibility: compatibility,
                version: version,
                author: author,
                tags: tags
            )
        }

        // AgentConfiguration（maxSteps をフロントマターから読む）
        var configuration = AgentConfiguration.default
        if let maxSteps = frontmatter.int("max-steps") {
            configuration = AgentConfiguration(maxSteps: maxSteps)
        }

        // モデルティア（整数 or light/standard/powerful の文字列）
        let modelTier: ModelTier
        if let tierInt = frontmatter.int("model-tier") {
            guard let tier = ModelTier(rawValue: tierInt) else {
                throw SkillError.invalidModelTier(String(tierInt))
            }
            modelTier = tier
        } else if let tierValue = frontmatter.string("model-tier") {
            switch tierValue.lowercased() {
            case "light": modelTier = .light
            case "standard": modelTier = .standard
            case "powerful": modelTier = .powerful
            default: throw SkillError.invalidModelTier(tierValue)
            }
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
            allowedTools: allowedTools,
            configuration: configuration,
            availability: availability,
            displayName: displayName,
            iconName: iconName,
            category: category,
            displayOrder: displayOrder,
            invocationMode: invocationMode,
            argumentHint: argumentHint,
            metadata: metadata,
            modelTier: modelTier,
            isEphemeral: isEphemeral
        )
    }
}
