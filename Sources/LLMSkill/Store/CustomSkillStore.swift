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
    public func loadAll() async throws -> [AgentSkillDefinition] {
        return try await Task.detached { [weak self] () -> [AgentSkillDefinition] in
            guard let self = self else { return [] }
            let fm = FileManager.default
            guard fm.fileExists(atPath: self.directory.path) else { return [] }
            return try SkillLoader.loadSkills(from: self.directory)
        }.value
    }

    /// カスタムスキルを保存
    ///
    /// `{name}/SKILL.md` 形式でファイルに書き込みます。
    /// 既存ファイルがあれば上書き。
    public func save(_ data: CustomSkillFormData) async throws {
        let content = generateSkillMD(from: data)
        let dir = directory
        try await Task.detached {
            let skillDir = dir.appendingPathComponent(data.name)
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let fileURL = skillDir.appendingPathComponent("SKILL.md")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }.value
    }

    /// カスタムスキルを削除
    ///
    /// `{name}/` ディレクトリごと削除します。
    public func delete(name: String) async throws {
        return try await Task.detached { [weak self] in
            guard let self = self else { return }
            let skillDir = self.directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: skillDir.path) {
                try FileManager.default.removeItem(at: skillDir)
            }
        }.value
    }

    // MARK: - Private

    /// SKILL.md テキストを生成
    private func generateSkillMD(from data: CustomSkillFormData) -> String {
        var yaml = "---\n"
        yaml += "name: \(yamlQuote(data.name))\n"
        yaml += "description: \(yamlQuote(data.description))\n"
        yaml += "context: \(data.executionMode.rawValue)\n"

        if !data.displayName.isEmpty && data.displayName != data.name {
            yaml += "display-name: \(yamlQuote(data.displayName))\n"
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
            yaml += "category: \(yamlQuote(category))\n"
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

    // MARK: - YAML Escaping

    /// YAML の値をエスケープする
    ///
    /// 特殊文字（コロン、ダブルクォート、改行、ハッシュ、シングルクォート）を含む場合、
    /// 値をダブルクォートで囲み、内部のバックスラッシュとダブルクォートをエスケープする。
    private func yamlQuote(_ value: String) -> String {
        guard value.contains(":") || value.contains("\"") || value.contains("\n") || value.contains("#") || value.contains("'") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
