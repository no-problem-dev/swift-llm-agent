import Foundation
import LLMAgent
import LLMClient

// MARK: - CustomSubAgentFormData

/// カスタムサブエージェント作成・編集フォーム用のデータ型
public struct CustomSubAgentFormData: Sendable {
    public var name: String
    public var description: String
    public var displayName: String
    public var iconName: String
    public var modelTier: ModelTier
    public var maxSteps: Int?
    public var allowedTools: [String]
    public var instructions: String

    public init(
        name: String = "",
        description: String = "",
        displayName: String = "",
        iconName: String = "person.circle",
        modelTier: ModelTier = .standard,
        maxSteps: Int? = nil,
        allowedTools: [String] = [],
        instructions: String = ""
    ) {
        self.name = name
        self.description = description
        self.displayName = displayName
        self.iconName = iconName
        self.modelTier = modelTier
        self.maxSteps = maxSteps
        self.allowedTools = allowedTools
        self.instructions = instructions
    }
}

// MARK: - CustomSubAgentStore

/// カスタムサブエージェントの永続化ストア
///
/// 指定ディレクトリ配下の `{name}/AGENT.md` ファイルを管理します。
/// スコープごとに異なるインスタンスを生成して使用します。
///
/// ## 使用例
///
/// ```swift
/// let store = CustomSubAgentStore(directory: agentsDirectory)
/// let agents = try await store.loadAll()
/// try await store.save(formData)
/// try await store.delete(name: "my-agent")
/// ```
public actor CustomSubAgentStore {

    private let directory: URL

    /// - Parameter directory: エージェントファイルのルートディレクトリ（例: `agents/`）
    public init(directory: URL) {
        self.directory = directory
    }

    /// 全カスタムエージェントタイプを読み込み
    ///
    /// ディレクトリ内の全 AGENT.md をパースして返します。
    public func loadAll() async throws -> [SubAgentTypeDefinition] {
        let dir = self.directory
        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: dir.path) else { return [] }
            return try SubAgentTypeLoader.loadAgentTypes(from: dir)
        }.value
    }

    /// カスタムエージェントタイプを保存
    ///
    /// `{name}/AGENT.md` 形式でファイルに書き込みます。
    /// 既存ファイルがあれば上書き。
    public func save(_ data: CustomSubAgentFormData) async throws {
        let content = generateAgentMD(from: data)
        let dir = directory
        try await Task.detached {
            let agentDir = dir.appendingPathComponent(data.name)
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let fileURL = agentDir.appendingPathComponent("AGENT.md")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }.value
    }

    /// カスタムエージェントタイプを削除
    ///
    /// `{name}/` ディレクトリごと削除します。
    public func delete(name: String) async throws {
        let dir = self.directory
        try await Task.detached(priority: .userInitiated) {
            let agentDir = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: agentDir.path) {
                try FileManager.default.removeItem(at: agentDir)
            }
        }.value
    }

    // MARK: - Private

    /// AGENT.md テキストを生成
    private func generateAgentMD(from data: CustomSubAgentFormData) -> String {
        var yaml = "---\n"
        yaml += "name: \(yamlQuote(data.name))\n"
        yaml += "description: \(yamlQuote(data.description))\n"

        if !data.displayName.isEmpty && data.displayName != data.name {
            yaml += "display-name: \(yamlQuote(data.displayName))\n"
        }
        if data.iconName != "person.circle" {
            yaml += "icon: \(data.iconName)\n"
        }

        let tierName: String
        switch data.modelTier {
        case .light: tierName = "light"
        case .standard: tierName = "standard"
        case .powerful: tierName = "powerful"
        }
        yaml += "model-tier: \(tierName)\n"

        if let maxSteps = data.maxSteps {
            yaml += "max-steps: \(maxSteps)\n"
        }

        yaml += "allowed-tools:\n"
        for tool in data.allowedTools {
            yaml += "  - \(tool)\n"
        }

        yaml += "---\n\n"
        yaml += data.instructions
        if !data.instructions.hasSuffix("\n") {
            yaml += "\n"
        }

        return yaml
    }

}
