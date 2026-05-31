import Foundation
import StructuredDataCore
import LLMAgent
import LLMClient

// MARK: - SubAgentTypeLoader

/// AGENT.md ファイルからサブエージェントタイプを読み込むローダー
///
/// `SkillLoader` と対称的な設計で、AGENT.md 形式（YAML フロントマター + Markdown 本文）を
/// パースし、`SubAgentTypeDefinition` に変換します。
///
/// ## AGENT.md 形式
///
/// ```markdown
/// ---
/// name: my-researcher
/// description: Custom web research agent
/// display-name: マイリサーチャー
/// icon: magnifyingglass.circle
/// model-tier: standard
/// max-steps: 12
/// allowed-tools:
///   - web_search
///   - web_fetch
/// ---
///
/// # System Prompt
///
/// You are a specialized research agent...
/// ```
///
/// ## 使用例
///
/// ```swift
/// // ディレクトリから全エージェントを読み込み
/// let agents = try SubAgentTypeLoader.loadAgentTypes(from: agentsDirectory)
///
/// // 単一ファイルを読み込み
/// let agent = try SubAgentTypeLoader.loadAgentType(from: agentFileURL)
///
/// // 文字列からパース
/// let agent = try SubAgentTypeLoader.parse(content: markdownString)
/// ```
public enum SubAgentTypeLoader {

    /// ディレクトリ内の全 AGENT.md ファイルを読み込み
    ///
    /// 指定ディレクトリ直下とサブディレクトリの `AGENT.md` ファイルを
    /// 再帰的に検索して読み込みます。
    ///
    /// - Parameter directory: 検索するディレクトリの URL
    /// - Returns: 読み込まれたエージェントタイプの配列
    /// - Throws: ファイル読み込みまたはパースエラー
    public static func loadAgentTypes(from directory: URL) throws -> [SubAgentTypeDefinition] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var agentTypes: [SubAgentTypeDefinition] = []

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "AGENT.md" {
                do {
                    let agentType = try loadAgentType(from: fileURL)
                    agentTypes.append(agentType)
                } catch {
                    throw SubAgentLoaderError.fileLoadError(fileURL, error)
                }
            }
        }

        return agentTypes
    }

    /// 単一の AGENT.md ファイルを読み込み
    ///
    /// - Parameter file: AGENT.md ファイルの URL
    /// - Returns: パースされたエージェントタイプ定義
    /// - Throws: ファイル読み込みまたはパースエラー
    public static func loadAgentType(from file: URL) throws -> SubAgentTypeDefinition {
        let content: String
        do {
            content = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw SubAgentLoaderError.fileLoadError(file, error)
        }
        return try parse(content: content)
    }

    /// AGENT.md 形式の文字列をパース
    ///
    /// - Parameter content: YAML フロントマター + Markdown 本文
    /// - Returns: パースされたエージェントタイプ定義
    /// - Throws: パースエラー
    public static func parse(content: String) throws -> SubAgentTypeDefinition {
        let frontmatter: StructuredValue
        let body: String
        do {
            (frontmatter, body) = try FrontmatterParser.parse(content)
        } catch let error as FrontmatterParseError {
            throw SubAgentLoaderError.missingRequiredField("frontmatter: \(error.localizedDescription)")
        }

        let fields: Fields
        do {
            fields = try frontmatter.decode(Fields.self)
        } catch {
            throw SubAgentLoaderError.missingRequiredField("frontmatter: \(error)")
        }

        // 必須フィールド
        guard let name = fields.name else {
            throw SubAgentLoaderError.missingRequiredField("name")
        }
        guard let description = fields.description else {
            throw SubAgentLoaderError.missingRequiredField("description")
        }

        // 許可ツール（必須）
        guard let allowedTools = fields.allowedTools else {
            throw SubAgentLoaderError.missingAllowedTools(name)
        }

        // モデルティア（整数 or light/standard/powerful の文字列）
        let modelTier: ModelTier
        if let spec = fields.modelTier {
            guard let resolved = spec.resolved else {
                throw SubAgentLoaderError.invalidModelTier(spec.description)
            }
            modelTier = resolved
        } else {
            modelTier = .standard
        }

        // AgentConfiguration（maxSteps をフロントマターから読む）
        var configuration = AgentConfiguration.default
        if let maxSteps = fields.maxSteps {
            configuration = AgentConfiguration(maxSteps: maxSteps)
        }

        // 本文（system prompt）
        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            throw SubAgentLoaderError.emptyInstructions
        }

        let systemPrompt = SystemPrompt(stringLiteral: instructions)

        return SubAgentTypeDefinition(
            name: name,
            description: description,
            displayName: fields.displayName,
            iconName: fields.icon,
            allowedTools: allowedTools,
            systemPrompt: systemPrompt,
            configuration: configuration,
            modelTier: modelTier
        )
    }

    /// AGENT.md フロントマターの型付き表現。文字列キーは ``CodingKeys`` の一箇所に封じ込める。
    private struct Fields: Decodable {
        let name: String?
        let description: String?
        let allowedTools: [String]?
        let displayName: String?
        let icon: String?
        let maxSteps: Int?
        let modelTier: ModelTier.Spec?

        enum CodingKeys: String, CodingKey {
            case name, description, icon
            case allowedTools = "allowed-tools"
            case displayName = "display-name"
            case maxSteps = "max-steps"
            case modelTier = "model-tier"
        }
    }
}
