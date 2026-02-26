import Foundation
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
        let (frontmatter, body) = try FrontmatterParser.parse(content)

        // 必須フィールド
        guard let name = frontmatter["name"] as? String else {
            throw SkillError.missingRequiredField("name")
        }
        guard let description = frontmatter["description"] as? String else {
            throw SkillError.missingRequiredField("description")
        }

        // 実行モード（context フィールド）
        let executionMode: SkillExecutionMode
        if let contextStr = frontmatter["context"] as? String {
            guard let mode = SkillExecutionMode(rawValue: contextStr) else {
                throw SkillError.invalidExecutionMode(contextStr)
            }
            executionMode = mode
        } else {
            executionMode = .inline
        }

        // 許可ツール
        let allowedTools = frontmatter["allowed-tools"] as? [String]

        // 呼び出し制御
        let isUserInvocable = frontmatter["user-invocable"] as? Bool ?? true
        let disableModel = frontmatter["disable-model-invocation"] as? Bool ?? false
        let argumentHint = frontmatter["argument-hint"] as? String

        // メタデータ
        let license = frontmatter["license"] as? String
        let compatibility = frontmatter["compatibility"] as? String
        let version = frontmatter["version"] as? String
        let author = frontmatter["author"] as? String

        var metadata: SkillMetadata? = nil
        if license != nil || compatibility != nil || version != nil || author != nil {
            metadata = SkillMetadata(
                license: license,
                compatibility: compatibility,
                version: version,
                author: author
            )
        }

        // AgentConfiguration（maxSteps をフロントマターから読む）
        var configuration = AgentConfiguration.default
        if let maxStepsValue = frontmatter["max-steps"] as? String,
           let maxSteps = Int(maxStepsValue)
        {
            configuration = AgentConfiguration(maxSteps: maxSteps)
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
            isUserInvocable: isUserInvocable,
            isModelInvocable: !disableModel,
            argumentHint: argumentHint,
            metadata: metadata
        )
    }
}
