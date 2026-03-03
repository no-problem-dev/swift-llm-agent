import Foundation
import LLMAgent

// MARK: - CustomSkillFormData

/// カスタムスキル作成・編集フォーム用のデータ型
public struct CustomSkillFormData: Sendable {
    public var name: String
    public var description: String
    public var displayName: String
    public var iconName: String
    public var executionMode: SkillExecutionMode
    public var allowedTools: [String]
    public var instructions: String
    public var modelTier: ModelTier
    public var category: String?

    public init(
        name: String = "",
        description: String = "",
        displayName: String = "",
        iconName: String = "sparkles",
        executionMode: SkillExecutionMode = .inline,
        allowedTools: [String] = [],
        instructions: String = "",
        modelTier: ModelTier = .standard,
        category: String? = nil
    ) {
        self.name = name
        self.description = description
        self.displayName = displayName
        self.iconName = iconName
        self.executionMode = executionMode
        self.allowedTools = allowedTools
        self.instructions = instructions
        self.modelTier = modelTier
        self.category = category
    }
}

// MARK: - CustomSkillStore

/// カスタムスキルの永続化ストア
///
/// 指定ディレクトリ配下の `{name}/SKILL.md` ファイルを管理します。
/// スコープごとに異なるインスタンスを生成して使用します。
///
/// ## 使用例
///
/// ```swift
/// let store = CustomSkillStore(directory: skillsDirectory)
/// let skills = try await store.loadAll()
/// try await store.save(formData)
/// try await store.delete(name: "my-skill")
/// ```
public actor CustomSkillStore {

    private let directory: URL

    /// - Parameter directory: スキルファイルのルートディレクトリ（例: `skills/`）
    public init(directory: URL) {
        self.directory = directory
    }

    /// 全カスタムスキルを読み込み
    ///
    /// ディレクトリ内の全 SKILL.md をパースして返します。
    public func loadAll() throws -> [AgentSkillDefinition] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try SkillLoader.loadSkills(from: directory)
    }

    /// カスタムスキルを保存
    ///
    /// `{name}/SKILL.md` 形式でファイルに書き込みます。
    /// 既存ファイルがあれば上書き。
    public func save(_ data: CustomSkillFormData) throws {
        let skillDir = directory.appendingPathComponent(data.name)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let fileURL = skillDir.appendingPathComponent("SKILL.md")
        let content = generateSkillMD(from: data)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// カスタムスキルを削除
    ///
    /// `{name}/` ディレクトリごと削除します。
    public func delete(name: String) throws {
        let skillDir = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: skillDir.path) {
            try FileManager.default.removeItem(at: skillDir)
        }
    }

    // MARK: - Private

    /// SKILL.md テキストを生成
    private func generateSkillMD(from data: CustomSkillFormData) -> String {
        var yaml = "---\n"
        yaml += "name: \(data.name)\n"
        yaml += "description: \(data.description)\n"
        yaml += "context: \(data.executionMode.rawValue)\n"

        if !data.displayName.isEmpty && data.displayName != data.name {
            yaml += "display-name: \(data.displayName)\n"
        }
        if data.iconName != "sparkles" {
            yaml += "icon: \(data.iconName)\n"
        }
        if data.modelTier != .standard {
            let tierName: String
            switch data.modelTier {
            case .light: tierName = "light"
            case .standard: tierName = "standard"
            case .powerful: tierName = "powerful"
            }
            yaml += "model-tier: \(tierName)\n"
        }
        if let category = data.category, !category.isEmpty {
            yaml += "category: \(category)\n"
        }
        if !data.allowedTools.isEmpty {
            yaml += "allowed-tools:\n"
            for tool in data.allowedTools {
                yaml += "  - \(tool)\n"
            }
        }

        yaml += "---\n\n"
        yaml += data.instructions
        if !data.instructions.hasSuffix("\n") {
            yaml += "\n"
        }

        return yaml
    }
}
