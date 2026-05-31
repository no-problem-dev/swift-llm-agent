import Foundation
import StructuredDataCore
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

    /// メッセージを送信し、結果（タスクまたはメッセージ）を返す
    func sendMessage(_ text: String, taskId: String?, contextId: String?) async throws -> A2ASendResult
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

// MARK: - A2ATaskState

/// タスクの状態（A2A 標準の状態を SDK 非依存に表現）。
public enum A2ATaskState: String, Sendable, Equatable {
    case submitted
    case working
    case inputRequired = "input-required"
    case completed
    case failed
    case canceled
    case rejected
    case authRequired = "auth-required"
    /// 未知・未指定。
    case unknown

    /// 終端状態（completed / failed / canceled / rejected）。
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .canceled, .rejected: true
        default: false
        }
    }
}

// MARK: - A2ATaskInfo

/// タスクの実行結果情報
///
/// A2A Task から変換された、SDKに依存しない情報型です。
public struct A2ATaskInfo: Sendable, Equatable {
    /// タスクID
    public let id: String

    /// コンテキストID（会話・セッションを束ねる識別子）
    public let contextId: String?

    /// タスクの状態
    public let state: A2ATaskState

    /// ステータスメッセージのテキスト
    public let statusMessage: String?

    /// アーティファクトのテキスト一覧
    public let artifactTexts: [String]

    public init(
        id: String,
        contextId: String? = nil,
        state: A2ATaskState,
        statusMessage: String? = nil,
        artifactTexts: [String] = []
    ) {
        self.id = id
        self.contextId = contextId
        self.state = state
        self.statusMessage = statusMessage
        self.artifactTexts = artifactTexts
    }

    /// 完了しているかどうか
    public var isCompleted: Bool { state == .completed }

    /// 失敗しているかどうか
    public var isFailed: Bool { state == .failed }

    /// 入力が必要かどうか
    public var isInputRequired: Bool { state == .inputRequired }

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

// MARK: - A2AMessageInfo

/// メッセージ応答情報（エージェントがタスクではなくメッセージを返した場合）。
public struct A2AMessageInfo: Sendable, Equatable {
    /// メッセージID
    public let messageId: String

    /// コンテキストID
    public let contextId: String?

    /// 関連タスクID
    public let taskId: String?

    /// 本文テキスト
    public let text: String

    public init(messageId: String, contextId: String? = nil, taskId: String? = nil, text: String) {
        self.messageId = messageId
        self.contextId = contextId
        self.taskId = taskId
        self.text = text
    }
}

// MARK: - A2ASendResult

/// メッセージ送信の結果（A2A 標準どおりタスクまたはメッセージのいずれか）。
public enum A2ASendResult: Sendable, Equatable {
    case task(A2ATaskInfo)
    case message(A2AMessageInfo)

    /// 応答テキスト（タスクなら responseText、メッセージなら本文）。
    public var responseText: String {
        switch self {
        case .task(let task): task.responseText
        case .message(let message): message.text
        }
    }

    /// 失敗したタスクかどうか。
    public var isFailed: Bool {
        if case .task(let task) = self { return task.isFailed }
        return false
    }

    /// タスク結果（あれば）。
    public var task: A2ATaskInfo? {
        if case .task(let task) = self { return task }
        return nil
    }

    /// メッセージ結果（あれば）。
    public var message: A2AMessageInfo? {
        if case .message(let message) = self { return message }
        return nil
    }

    /// コンテキストID（タスク・メッセージ共通）。
    public var contextId: String? {
        switch self {
        case .task(let task): task.contextId
        case .message(let message): message.contextId
        }
    }
}

// MARK: - A2AAgent

/// A2Aエージェントへの接続を表す具象型
///
/// リモートA2Aエージェントに接続し、スキル（ツール）を取得・実行します。
/// 対応バインディングは Agent Card の `supportedInterfaces` から自動選択されます
/// （JSON-RPC 優先・REST フォールバック）。
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

    /// SDK を隠蔽するアダプタ（バインディング交渉とカードを内部でキャッシュ）。
    private let adapter: A2AClientAdapter

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
        self.adapter = A2AClientAdapter(url: url, authentication: authentication, timeout: timeout)
    }

    // MARK: - A2AAgentProtocol

    public func fetchAgentInfo() async throws -> A2AAgentInfo {
        try await adapter.fetchAgentInfo()
    }

    public func fetchTools() async throws -> [A2AAgentTool] {
        let agentInfo = try await adapter.fetchAgentInfo()
        let agentName = self.agentName
        let adapter = self.adapter

        // 各スキルをA2AAgentToolに変換
        return agentInfo.skills.map { skill in
            let skillName = skill.name
            let skillId = skill.id

            return A2AAgentTool(
                name: "\(agentName)_\(skill.id)",
                description: skill.description ?? "Skill '\(skillName)' from A2A agent '\(agentName)'",
                skillId: skillId,
                agentName: agentName
            ) { argumentsData in
                // 引数からテキストを抽出
                let text: String
                if argumentsData.isEmpty {
                    text = ""
                } else if let args = try? JSONParser().parse(argumentsData).decode(A2AMessageArguments.self),
                          let message = args.message {
                    text = message
                } else {
                    text = String(data: argumentsData, encoding: .utf8) ?? ""
                }

                let result = try await adapter.sendMessage(text: text)
                if result.isFailed {
                    return .error(result.responseText.isEmpty ? "Task failed" : result.responseText)
                }
                return .text(result.responseText.isEmpty ? "OK" : result.responseText)
            }
        }
    }

    public func sendMessage(
        _ text: String,
        taskId: String? = nil,
        contextId: String? = nil
    ) async throws -> A2ASendResult {
        try await adapter.sendMessage(text: text, taskId: taskId, contextId: contextId)
    }
}

// MARK: - Tool Argument DTO

/// A2A スキルツールの引数。文字列キーはこの型の ``CodingKeys`` に封じ込める。
private struct A2AMessageArguments: Decodable {
    let message: String?
}
