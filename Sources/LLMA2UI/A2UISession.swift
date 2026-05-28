import A2UICore
import A2UIPrompt
import A2UISurface
import Foundation
import LLMAgent
import LLMClient
import LLMTool

/// A2UI セッション。1 つの会話スレッドを表す。
///
/// 役割:
/// - LLM とのターン実行 (`send` / `handleAction`)
/// - 会話履歴の保持（tool use / tool result を含む完全な列）
/// - サーフェス状態の管理（公開している `messageProcessor` 経由）
///
/// `messageProcessor` は `@MainActor + @Observable` で、SwiftUI から直接 bind できる。
///
/// ```swift
/// let session = A2UISession(client: client, model: .sonnet)
///
/// // Turn 1
/// for try await step in session.send("予約フォームを作って") {
///     // step を処理
/// }
///
/// // SurfaceView などからは session.messageProcessor.surface(id:) で取得
/// ```
@MainActor
public final class A2UISession<Client: AgentCapableClient> where Client.Model: Sendable {
    private let client: Client
    /// 使用するモデル。ターン実行中に変更しても、次ターンから反映される。
    public var model: Client.Model
    private let tools: ToolSet
    private let systemPrompt: SystemPrompt
    private let agentConfiguration: AgentConfiguration
    private let a2uiConfiguration: A2UIAgentConfiguration

    /// SwiftUI が bind する surface state。
    public let messageProcessor: MessageProcessor

    /// 会話履歴。tool use / tool result も含む完全な列。
    public private(set) var conversationHistory: [LLMMessage] = []

    public init(
        client: Client,
        model: Client.Model,
        tools: ToolSet = ToolSet {},
        messageProcessor: MessageProcessor = MessageProcessor(),
        promptConfiguration: A2UIPromptConfiguration = .default,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) {
        self.client = client
        self.model = model
        self.tools = tools
        self.messageProcessor = messageProcessor
        self.agentConfiguration = agentConfiguration
        self.a2uiConfiguration = a2uiConfiguration
        self.systemPrompt = promptConfiguration.makeSystemPrompt()
    }

    // MARK: - Public API

    /// ユーザーのテキスト入力で新しいターンを実行する。
    public func send(_ input: String) -> AsyncThrowingStream<A2UISessionStep, Error> {
        executeTurn(userContent: input)
    }

    /// UserAction（ボタン押下等）で新しいターンを実行する。
    /// `sendDataModel == true` の Surface のデータモデルが自動で会話に注入される。
    public func handleAction(_ action: UserAction) -> AsyncThrowingStream<A2UISessionStep, Error> {
        let actionJSON = (try? String(data: JSONEncoder().encode(action), encoding: .utf8)) ?? "{}"
        return executeTurn(userContent: "[A2UI Action] \(actionJSON)")
    }

    /// 会話履歴とサーフェス状態をクリアする。
    public func reset() {
        conversationHistory.removeAll()
        messageProcessor.removeAll()
    }

    // MARK: - Internal

    private func executeTurn(userContent: String) -> AsyncThrowingStream<A2UISessionStep, Error> {
        let client = self.client
        let model = self.model
        let tools = self.tools
        let systemPrompt = self.systemPrompt
        let agentConfig = self.agentConfiguration
        let a2uiConfig = self.a2uiConfiguration
        let history = self.conversationHistory
        let messageProcessor = self.messageProcessor

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                do {
                    var messages = history
                    if let ctx = Self.buildDataModelContext(processor: messageProcessor) {
                        messages.append(.user(ctx))
                    }
                    messages.append(.user(userContent))

                    let stream = A2UIAgentStepSequence(
                        client: client,
                        model: model,
                        initialMessages: messages,
                        tools: tools,
                        systemPrompt: systemPrompt,
                        agentConfiguration: agentConfig,
                        a2uiConfiguration: a2uiConfig
                    )

                    for try await step in stream {
                        switch step {
                        case .thinking(let response):
                            continuation.yield(.thinking(response))
                        case .toolCall(let call):
                            continuation.yield(.toolCall(call))
                        case .toolResult(let result):
                            continuation.yield(.toolResult(result))
                        case .responsePart(let part):
                            if let text = part.text {
                                continuation.yield(.text(text))
                            }
                            if let serverMessages = part.messages {
                                let existing = Set(messageProcessor.surfaces.keys)
                                let healed = SurfaceIdHealer.heal(serverMessages, existing: existing)
                                _ = messageProcessor.process(healed)
                                for serverMessage in healed {
                                    continuation.yield(.surfaceUpdated(Self.extractSurfaceId(from: serverMessage)))
                                }
                            }
                        case .decodeEvent(let event):
                            continuation.yield(.decodeEvent(event))
                        case .turnCompleted(let finalMessages):
                            self?.conversationHistory = finalMessages
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// `sendDataModel == true` のサーフェスのデータモデルを会話に注入するためのコンテキストを構築。
    private static func buildDataModelContext(processor: MessageProcessor) -> String? {
        let active = processor.surfaces.values.filter { $0.sendDataModel }
        guard !active.isEmpty else {
            return nil
        }

        var context: [String: AnyCodable] = [:]
        for surface in active {
            context[surface.id] = surface.dataModel.snapshot
        }

        guard let data = try? JSONEncoder().encode(context),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return "[A2UI Client Data Model] \(json)"
    }

    private static func extractSurfaceId(from message: ServerMessage) -> String {
        switch message {
        case .createSurface(let m): m.surfaceId
        case .updateComponents(let m): m.surfaceId
        case .updateDataModel(let m): m.surfaceId
        case .deleteSurface(let m): m.surfaceId
        }
    }
}
