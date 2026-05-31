import Foundation
import JSONParsing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LLMClient
import LLMTool

// MARK: - A2AAgentProtocol

/// A2Aエージェントを表すプロトコル
///
/// A2Aエージェントはリモートエージェントにメッセージを送信し、
/// スキル（ツール）を動的に取得できます。
public protocol A2AAgentProtocol: Sendable {
    /// エージェント名
    var agentName: String { get }

    /// エージェントURL
    var agentURL: URL { get }

    /// エージェント情報を取得
    func fetchAgentInfo() async throws -> A2AAgentInfo

    /// エージェントのスキルをツールとして取得
    func fetchTools() async throws -> [A2AAgentTool]

    /// メッセージを送信
    func sendMessage(_ text: String, taskId: String?, sessionId: String?) async throws -> A2ATaskInfo
}

// MARK: - A2AAuthentication

/// A2Aエージェントへの認証方式
///
/// リモートA2Aエージェントとの通信に使用される認証設定です。
///
/// ## 使用例
///
/// ```swift
/// // Bearer トークン認証
/// A2AAgent(url: url, authentication: .bearer("your-token"))
///
/// // APIキー認証
/// A2AAgent(url: url, authentication: .apiKey("X-API-Key", "your-key"))
/// ```
public enum A2AAuthentication: Sendable {
    /// Bearer トークン認証
    case bearer(String)

    /// APIキー認証
    case apiKey(String, String)

    /// カスタムヘッダー
    case headers([String: String])

    /// 認証なし
    case none
}

// MARK: - A2AAgentInfo

/// エージェントのメタデータ情報
///
/// A2A AgentCard から変換された、SDKに依存しない情報型です。
public struct A2AAgentInfo: Sendable, Equatable {
    /// エージェント名
    public let name: String

    /// エージェントの説明
    public let description: String?

    /// バージョン
    public let version: String?

    /// スキル一覧
    public let skills: [A2ASkillInfo]

    /// ストリーミングサポート
    public let supportsStreaming: Bool

    /// プッシュ通知サポート
    public let supportsPushNotifications: Bool

    public init(
        name: String,
        description: String? = nil,
        version: String? = nil,
        skills: [A2ASkillInfo] = [],
        supportsStreaming: Bool = false,
        supportsPushNotifications: Bool = false
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.skills = skills
        self.supportsStreaming = supportsStreaming
        self.supportsPushNotifications = supportsPushNotifications
    }
}

// MARK: - A2ASkillInfo

/// エージェントのスキル情報
public struct A2ASkillInfo: Sendable, Equatable {
    /// スキルID
    public let id: String

    /// スキル名
    public let name: String

    /// スキルの説明
    public let description: String?

    /// タグ
    public let tags: [String]

    public init(id: String, name: String, description: String? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
    }
}

// MARK: - A2ATaskInfo

/// タスクの実行結果情報
///
/// A2A Task から変換された、SDKに依存しない情報型です。
public struct A2ATaskInfo: Sendable, Equatable {
    /// タスクID
    public let id: String

    /// セッションID
    public let sessionId: String?

    /// タスクの状態
    public let state: String

    /// ステータスメッセージのテキスト
    public let statusMessage: String?

    /// アーティファクトのテキスト一覧
    public let artifactTexts: [String]

    public init(
        id: String,
        sessionId: String? = nil,
        state: String,
        statusMessage: String? = nil,
        artifactTexts: [String] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.state = state
        self.statusMessage = statusMessage
        self.artifactTexts = artifactTexts
    }

    /// 完了しているかどうか
    public var isCompleted: Bool {
        state == "completed"
    }

    /// 失敗しているかどうか
    public var isFailed: Bool {
        state == "failed"
    }

    /// 入力が必要かどうか
    public var isInputRequired: Bool {
        state == "input-required"
    }

    /// レスポンステキスト（ステータスメッセージ + アーティファクト）
    public var responseText: String {
        var parts: [String] = []
        if let msg = statusMessage {
            parts.append(msg)
        }
        parts.append(contentsOf: artifactTexts)
        return parts.joined(separator: "\n")
    }
}

// MARK: - A2AAgent

/// A2Aエージェントへの接続を表す具象型
///
/// リモートA2Aエージェントに接続し、スキル（ツール）を取得・実行します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     A2AAgent(
///         url: URL(string: "https://agent.example.com")!,
///         authentication: .bearer("token")
///     )
/// }
///
/// let resolved = try await tools.resolvingA2AAgents()
/// ```
public struct A2AAgent: A2AAgentProtocol {
    // MARK: - Properties

    public let agentName: String
    public let agentURL: URL

    private let authentication: A2AAuthentication
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// A2Aエージェントに接続
    ///
    /// - Parameters:
    ///   - url: エージェントのベースURL
    ///   - name: エージェント名（デフォルトはホスト名）
    ///   - authentication: 認証設定
    ///   - timeout: タイムアウト（秒）
    public init(
        url: URL,
        name: String? = nil,
        authentication: A2AAuthentication = .none,
        timeout: TimeInterval = 60
    ) {
        self.agentURL = url
        self.agentName = name ?? url.host ?? "a2a-agent"
        self.authentication = authentication
        self.timeout = timeout
    }

    // MARK: - A2AAgentProtocol

    public func fetchAgentInfo() async throws -> A2AAgentInfo {
        let adapter = createAdapter()
        return try await adapter.fetchAgentInfo()
    }

    public func fetchTools() async throws -> [A2AAgentTool] {
        let adapter = createAdapter()
        let agentInfo = try await adapter.fetchAgentInfo()

        // 各スキルをA2AAgentToolに変換
        return agentInfo.skills.map { skill in
            // スキル名とエージェント名を取得（Sendable対応）
            let skillName = skill.name
            let skillId = skill.id
            let agentName = self.agentName

            return A2AAgentTool(
                name: "\(self.agentName)_\(skill.id)",
                description: skill.description ?? "Skill '\(skillName)' from A2A agent '\(agentName)'",
                skillId: skillId,
                agentName: agentName
            ) { [authentication, timeout, agentURL] argumentsData in
                // 引数からテキストを抽出
                let text: String
                if argumentsData.isEmpty {
                    text = ""
                } else if let json = try? JSONParser().parse(argumentsData),
                          let message = json.string("message") {
                    text = message
                } else {
                    text = String(data: argumentsData, encoding: .utf8) ?? ""
                }

                let execAdapter = A2AClientAdapter(
                    url: agentURL,
                    authentication: authentication,
                    timeout: timeout
                )
                let taskInfo = try await execAdapter.sendMessage(text: text)

                if taskInfo.isFailed {
                    return .error(taskInfo.responseText.isEmpty ? "Task failed" : taskInfo.responseText)
                }

                return .text(taskInfo.responseText.isEmpty ? "Task \(taskInfo.state)" : taskInfo.responseText)
            }
        }
    }

    public func sendMessage(
        _ text: String,
        taskId: String? = nil,
        sessionId: String? = nil
    ) async throws -> A2ATaskInfo {
        let adapter = createAdapter()
        return try await adapter.sendMessage(text: text, taskId: taskId, sessionId: sessionId)
    }

    // MARK: - Private

    private func createAdapter() -> A2AClientAdapter {
        A2AClientAdapter(url: agentURL, authentication: authentication, timeout: timeout)
    }
}
