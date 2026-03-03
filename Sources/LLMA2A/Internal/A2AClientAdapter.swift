import A2A
import Foundation
import LLMTool

/// A2A SDKのA2AClientをラップし、自前の型に変換するアダプター
///
/// SDKの詳細をカプセル化し、LLMA2Aモジュールの公開APIから
/// SDKの型を隠蔽します。
internal actor A2AClientAdapter {
    // MARK: - Properties

    private let client: A2A.A2AClient

    // MARK: - Initialization

    /// A2Aクライアントアダプターを作成
    ///
    /// - Parameters:
    ///   - url: A2AエージェントのベースURL
    ///   - authentication: 認証設定
    ///   - timeout: タイムアウト（秒）
    init(url: URL, authentication: A2AAuthentication, timeout: TimeInterval = 60) {
        let sdkAuth = Self.convertAuthentication(authentication)
        let config = A2A.A2AClientConfiguration(
            baseURL: url,
            authentication: sdkAuth,
            timeout: timeout
        )
        self.client = A2A.A2AClient(configuration: config)
    }

    // MARK: - Agent Card

    /// エージェントカードを取得し、A2AAgentInfo型に変換
    func fetchAgentInfo() async throws -> A2AAgentInfo {
        let card = try await client.fetchAgentCard()
        return convertToAgentInfo(card)
    }

    // MARK: - Message Sending

    /// メッセージを送信し、タスク情報を返す
    ///
    /// - Parameters:
    ///   - text: 送信するテキスト
    ///   - taskId: 既存タスクID（継続会話用）
    ///   - sessionId: セッションID
    /// - Returns: タスク情報
    func sendMessage(
        text: String,
        taskId: String? = nil,
        sessionId: String? = nil
    ) async throws -> A2ATaskInfo {
        let message = A2A.Message.user(text)
        var config: A2A.MessageSendConfiguration? = nil
        if taskId != nil || sessionId != nil {
            config = A2A.MessageSendConfiguration(
                taskId: taskId,
                sessionId: sessionId
            )
        }
        let task = try await client.sendMessage(message, configuration: config)
        return convertToTaskInfo(task)
    }

    /// メッセージをストリーミング送信
    ///
    /// - Parameters:
    ///   - text: 送信するテキスト
    ///   - taskId: 既存タスクID
    ///   - sessionId: セッションID
    /// - Returns: テキストチャンクの非同期ストリーム
    func streamMessage(
        text: String,
        taskId: String? = nil,
        sessionId: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let message = A2A.Message.user(text)
        var config: A2A.MessageSendConfiguration? = nil
        if taskId != nil || sessionId != nil {
            config = A2A.MessageSendConfiguration(
                taskId: taskId,
                sessionId: sessionId
            )
        }
        let stream = try await client.streamMessage(message, configuration: config)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        switch event {
                        case .statusUpdate(let statusEvent):
                            if let message = statusEvent.status.message {
                                let text = Self.extractText(from: message)
                                if !text.isEmpty {
                                    continuation.yield(text)
                                }
                            }
                        case .artifactUpdate(let artifactEvent):
                            let text = Self.extractTextFromParts(artifactEvent.artifact.parts)
                            if !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Task Operations

    /// タスクを取得
    func getTask(id: String) async throws -> A2ATaskInfo {
        let task = try await client.getTask(id: id)
        return convertToTaskInfo(task)
    }

    /// タスクをキャンセル
    func cancelTask(id: String) async throws -> A2ATaskInfo {
        let task = try await client.cancelTask(id: id)
        return convertToTaskInfo(task)
    }

    // MARK: - Conversion Helpers

    /// 認証設定を変換
    private static func convertAuthentication(_ auth: A2AAuthentication) -> A2A.A2AAuthentication {
        switch auth {
        case .bearer(let token):
            return .bearer(token)
        case .apiKey(let name, let value):
            return .apiKey(headerName: name, value: value)
        case .headers(let headers):
            return .headers(headers)
        case .none:
            return .none
        }
    }

    /// AgentCardをA2AAgentInfoに変換
    private func convertToAgentInfo(_ card: A2A.AgentCard) -> A2AAgentInfo {
        let skills = card.skills?.map { skill in
            A2ASkillInfo(
                id: skill.id,
                name: skill.name,
                description: skill.description,
                tags: skill.tags ?? []
            )
        } ?? []

        return A2AAgentInfo(
            name: card.name,
            description: card.description,
            version: card.version,
            skills: skills,
            supportsStreaming: card.capabilities?.streaming ?? false,
            supportsPushNotifications: card.capabilities?.pushNotifications ?? false
        )
    }

    /// A2ATaskをA2ATaskInfoに変換
    private func convertToTaskInfo(_ task: A2A.A2ATask) -> A2ATaskInfo {
        let stateString: String
        switch task.status.state {
        case .submitted: stateString = "submitted"
        case .working: stateString = "working"
        case .inputRequired: stateString = "input-required"
        case .completed: stateString = "completed"
        case .canceled: stateString = "canceled"
        case .failed: stateString = "failed"
        case .unknown: stateString = "unknown"
        case .authRequired: stateString = "auth-required"
        }

        // ステータスメッセージのテキストを抽出
        let statusText: String?
        if let message = task.status.message {
            let text = Self.extractText(from: message)
            statusText = text.isEmpty ? nil : text
        } else {
            statusText = nil
        }

        // アーティファクトからテキストを抽出
        let artifactTexts = task.artifacts?.compactMap { artifact -> String? in
            let text = Self.extractTextFromParts(artifact.parts)
            return text.isEmpty ? nil : text
        } ?? []

        return A2ATaskInfo(
            id: task.id,
            sessionId: task.sessionId,
            state: stateString,
            statusMessage: statusText,
            artifactTexts: artifactTexts
        )
    }

    /// メッセージからテキストを抽出
    private static func extractText(from message: A2A.Message) -> String {
        extractTextFromParts(message.parts)
    }

    /// パート配列からテキストを抽出
    private static func extractTextFromParts(_ parts: [A2A.Part]) -> String {
        parts.compactMap { part in
            switch part {
            case .text(let textPart):
                return textPart.text
            case .file, .data:
                return nil
            }
        }.joined(separator: "\n")
    }
}
