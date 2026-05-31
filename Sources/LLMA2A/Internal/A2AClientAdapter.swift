import A2AClientJSONRPC
import A2AClientREST
import Foundation
import LLMTool

/// swift-a2a の `A2AClient` をラップし、自前の中立 DTO に変換するアダプター。
///
/// SDK の詳細をカプセル化し、LLMA2A の公開 API から SDK 型を隠蔽します。
/// 初回利用時に Agent Card を取得し、`supportedInterfaces` から対応バインディング
/// （JSON-RPC 優先・REST フォールバック）を選択します。カードが取得できない場合は
/// 与えられた URL に対する JSON-RPC へフォールバックします。
internal actor A2AClientAdapter {
    // MARK: - Properties

    private let baseURL: URL
    private let authentication: A2AAuthentication
    private let timeout: TimeInterval

    private var clientCache: A2AClient?
    private var cardCache: AgentCard?

    // MARK: - Initialization

    init(url: URL, authentication: A2AAuthentication, timeout: TimeInterval = 60) {
        self.baseURL = url
        self.authentication = authentication
        self.timeout = timeout
    }

    // MARK: - Resolution (binding negotiation)

    /// 操作用クライアントを返す。未解決ならカード取得＋バインディング交渉を行い、
    /// 取得失敗時は JSON-RPC フォールバックを採用する（送信系操作を止めないため）。
    private func operationalClient() async -> A2AClient {
        if let client = clientCache { return client }

        let sdkAuth = Self.convertAuthentication(authentication)
        var client = A2AClient.jsonRPC(endpoint: baseURL, authentication: sdkAuth, timeout: timeout)

        if let card = try? await client.fetchAgentCard() {
            cardCache = card
            client = Self.makeClient(for: card, baseURL: baseURL, authentication: sdkAuth, timeout: timeout)
        }
        clientCache = client
        return client
    }

    /// Agent Card を返す（必須）。未取得なら取得し、合わせてクライアントも確定する。
    private func resolvedCard() async throws -> AgentCard {
        if let card = cardCache { return card }
        let sdkAuth = Self.convertAuthentication(authentication)
        let probe = A2AClient.jsonRPC(endpoint: baseURL, authentication: sdkAuth, timeout: timeout)
        let card = try await probe.fetchAgentCard()
        cardCache = card
        if clientCache == nil {
            clientCache = Self.makeClient(for: card, baseURL: baseURL, authentication: sdkAuth, timeout: timeout)
        }
        return card
    }

    /// `supportedInterfaces` から対応バインディングのクライアントを構築（JSON-RPC 優先・REST フォールバック）。
    private static func makeClient(
        for card: AgentCard,
        baseURL: URL,
        authentication: A2AClientCore.A2AAuthentication,
        timeout: TimeInterval
    ) -> A2AClient {
        func interface(_ binding: String) -> AgentInterface? {
            card.supportedInterfaces.first { $0.protocolBinding.uppercased() == binding }
        }
        if let jsonRPC = interface("JSONRPC"), let url = URL(string: jsonRPC.url) {
            return .jsonRPC(endpoint: url, authentication: authentication, timeout: timeout)
        }
        if let rest = interface("HTTP+JSON") ?? interface("REST"), let url = URL(string: rest.url) {
            return .rest(baseURL: url, authentication: authentication, timeout: timeout)
        }
        return .jsonRPC(endpoint: baseURL, authentication: authentication, timeout: timeout)
    }

    // MARK: - Agent Card

    func fetchAgentInfo() async throws -> A2AAgentInfo {
        convertToAgentInfo(try await resolvedCard())
    }

    // MARK: - Message Sending

    /// メッセージを送信し、結果（タスクまたはメッセージ）を返す。
    func sendMessage(
        text: String,
        taskId: String? = nil,
        contextId: String? = nil
    ) async throws -> A2ASendResult {
        let client = await operationalClient()
        let response = try await client.sendMessage(Self.makeMessage(text: text, taskId: taskId, contextId: contextId))
        switch response {
        case .task(let task):
            return .task(convertToTaskInfo(task))
        case .message(let message):
            return .message(Self.convertToMessageInfo(message))
        }
    }

    /// メッセージをストリーミング送信し、テキストチャンクを流す。
    func streamMessage(
        text: String,
        taskId: String? = nil,
        contextId: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let client = await operationalClient()
        let stream = try await client.streamMessage(Self.makeMessage(text: text, taskId: taskId, contextId: contextId))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        let text: String
                        switch event {
                        case .task(let task):
                            text = task.status.message.map(Self.extractText) ?? ""
                        case .message(let message):
                            text = Self.extractText(from: message)
                        case .statusUpdate(let update):
                            text = update.status.message.map(Self.extractText) ?? ""
                        case .artifactUpdate(let update):
                            text = Self.extractTextFromParts(update.artifact.parts)
                        }
                        if !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Task Operations

    func getTask(id: String) async throws -> A2ATaskInfo {
        let client = await operationalClient()
        return convertToTaskInfo(try await client.getTask(TaskID(id)))
    }

    func cancelTask(id: String) async throws -> A2ATaskInfo {
        let client = await operationalClient()
        return convertToTaskInfo(try await client.cancelTask(TaskID(id)))
    }

    // MARK: - Conversion Helpers

    private static func makeMessage(text: String, taskId: String?, contextId: String?) -> Message {
        Message(
            messageId: MessageID(UUID().uuidString),
            role: .user,
            parts: [.text(text)],
            contextId: contextId.map(ContextID.init),
            taskId: taskId.map(TaskID.init)
        )
    }

    private static func convertAuthentication(_ auth: A2AAuthentication) -> A2AClientCore.A2AAuthentication {
        switch auth {
        case .bearer(let token): .bearer(token)
        case .apiKey(let name, let value): .apiKey(header: name, value: value)
        case .headers(let headers): .headers(headers)
        case .none: .none
        }
    }

    private func convertToAgentInfo(_ card: AgentCard) -> A2AAgentInfo {
        let skills = card.skills.map { skill in
            A2ASkillInfo(id: skill.id, name: skill.name, description: skill.description, tags: skill.tags)
        }
        return A2AAgentInfo(
            name: card.name,
            description: card.description.isEmpty ? nil : card.description,
            version: card.version.isEmpty ? nil : card.version,
            skills: skills,
            supportsStreaming: card.capabilities.streaming ?? false,
            supportsPushNotifications: card.capabilities.pushNotifications ?? false
        )
    }

    private func convertToTaskInfo(_ task: A2ATask) -> A2ATaskInfo {
        let statusText = task.status.message.map(Self.extractText).flatMap { $0.isEmpty ? nil : $0 }
        let artifactTexts = task.artifacts.compactMap { artifact -> String? in
            let text = Self.extractTextFromParts(artifact.parts)
            return text.isEmpty ? nil : text
        }
        return A2ATaskInfo(
            id: task.id.rawValue,
            contextId: task.contextId?.rawValue,
            state: A2ATaskState(task.status.state),
            statusMessage: statusText,
            artifactTexts: artifactTexts
        )
    }

    private static func convertToMessageInfo(_ message: Message) -> A2AMessageInfo {
        A2AMessageInfo(
            messageId: message.messageId.rawValue,
            contextId: message.contextId?.rawValue,
            taskId: message.taskId?.rawValue,
            text: extractText(from: message)
        )
    }

    private static func extractText(from message: Message) -> String {
        extractTextFromParts(message.parts)
    }

    private static func extractTextFromParts(_ parts: [Part]) -> String {
        parts.compactMap(\.text).joined(separator: "\n")
    }
}

// MARK: - SDK 状態 → 中立状態の変換（SDK 隔離のためアダプタ層に配置）

extension A2ATaskState {
    init(_ sdk: A2ACore.TaskState) {
        switch sdk {
        case .submitted: self = .submitted
        case .working: self = .working
        case .inputRequired: self = .inputRequired
        case .completed: self = .completed
        case .failed: self = .failed
        case .canceled: self = .canceled
        case .rejected: self = .rejected
        case .authRequired: self = .authRequired
        case .unspecified: self = .unknown
        }
    }
}
