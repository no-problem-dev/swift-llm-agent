import A2UICore
import A2UIParser
import A2UIPrompt
import A2UISurface
import Foundation
import LLMAgent
import LLMClient
import LLMTool

/// A2UI セッション。Surface 状態を保持し、複数ターンに跨る A2UI データフローを管理する。
///
/// 1 セッション = 1 会話スレッド。Surface の状態はターン間で永続する。
///
/// ```swift
/// let session = A2UISession(client: client, model: .sonnet)
///
/// // Turn 1: ユーザー発話 → Surface 作成
/// for try await step in session.send("予約フォームを作って") {
///     if case .surfaceUpdated(let id) = step {
///         let state = await session.surface(id: id)
///         // state.components でレンダリング
///     }
/// }
///
/// // Turn 2: ユーザー操作 → Surface 更新
/// let action = UserAction(name: "submit", surfaceId: "s1", ...)
/// for try await step in session.handleAction(action) {
///     if case .surfaceUpdated(let id) = step { /* 再レンダリング */ }
/// }
/// ```
public actor A2UISession<Client: AgentCapableClient> where Client.Model: Sendable {
    private let client: Client
    private let model: Client.Model
    private let tools: ToolSet
    private let systemPrompt: SystemPrompt
    private let agentConfiguration: AgentConfiguration
    private let a2uiConfiguration: A2UIAgentConfiguration

    private let store: SurfaceStore
    private let coordinator: SurfaceCoordinator
    private var conversationHistory: [LLMMessage] = []

    public init(
        client: Client,
        model: Client.Model,
        tools: ToolSet = ToolSet {},
        role: String = "You are a helpful assistant that generates A2UI interfaces.",
        additionalSystemPrompt: SystemPrompt? = nil,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default
    ) {
        self.client = client
        self.model = model
        self.tools = tools
        self.agentConfiguration = agentConfiguration
        self.a2uiConfiguration = a2uiConfiguration

        let promptBuilder = A2UIPromptBuilder()
        let a2uiPrompt = promptBuilder.buildSystemPrompt(role: role)
        var prompt = SystemPrompt { PromptComponent.context(a2uiPrompt) }
        if let additional = additionalSystemPrompt {
            prompt = prompt + additional
        }
        self.systemPrompt = prompt

        self.store = SurfaceStore()
        self.coordinator = SurfaceCoordinator(store: store)
    }

    // MARK: - Surface State Access

    public func surface(id: String) async -> SurfaceState? {
        await store.surface(id: id)
    }

    public func allSurfaces() async -> [String: SurfaceState] {
        await store.surfaces
    }

    public func resolvedTree(surfaceId: String) async throws -> ComponentNode {
        try await coordinator.resolvedTree(surfaceId: surfaceId)
    }

    // MARK: - Turn Execution

    /// ユーザーのテキスト入力で新しいターンを実行する。
    public func send(_ input: String) -> AsyncThrowingStream<A2UISessionStep, Error> {
        executeTurn(userContent: input)
    }

    /// UserAction（ボタン押下等）で新しいターンを実行する。
    /// sendDataModel=true の Surface のデータモデルが自動で会話に注入される。
    public func handleAction(_ action: UserAction) -> AsyncThrowingStream<A2UISessionStep, Error> {
        let actionJSON = (try? String(data: JSONEncoder().encode(action), encoding: .utf8)) ?? "{}"
        return executeTurn(userContent: "[A2UI Action] \(actionJSON)")
    }

    // MARK: - Internal

    private func executeTurn(userContent: String) -> AsyncThrowingStream<A2UISessionStep, Error> {
        // Capture all state needed for the stream closure
        let client = self.client
        let model = self.model
        let tools = self.tools
        let systemPrompt = self.systemPrompt
        let agentConfig = self.agentConfiguration
        let a2uiConfig = self.a2uiConfiguration
        let history = self.conversationHistory
        let store = self.store
        let coordinator = self.coordinator

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    // Build messages: history + data model context + user message
                    var messages = history
                    let dataModelContext = await Self.buildDataModelContext(store: store)
                    if let ctx = dataModelContext {
                        messages.append(.user(ctx))
                    }
                    messages.append(.user(userContent))

                    // Run agent loop (full, with tools)
                    let stream = A2UIAgentStepSequence(
                        client: client,
                        model: model,
                        initialMessages: messages,
                        tools: tools,
                        systemPrompt: systemPrompt,
                        agentConfiguration: agentConfig,
                        a2uiConfiguration: a2uiConfig
                    )

                    var assistantText = ""

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
                                assistantText += text + "\n"
                                continuation.yield(.text(text))
                            }
                            if let serverMessages = part.messages {
                                for msg in serverMessages {
                                    await Self.applyMessage(msg, coordinator: coordinator, store: store)
                                    let surfaceId = Self.extractSurfaceId(from: msg)
                                    continuation.yield(.surfaceUpdated(surfaceId))
                                }
                            }
                        }
                    }

                    // Update conversation history
                    await self?.updateHistory(userContent: userContent, assistantText: assistantText)

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func updateHistory(userContent: String, assistantText: String) {
        conversationHistory.append(.user(userContent))
        if !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversationHistory.append(.assistant(assistantText))
        }
    }

    /// sendDataModel=true の Surface のデータモデルを会話に注入するコンテキストを構築。
    private static func buildDataModelContext(store: SurfaceStore) async -> String? {
        let surfaces = await store.surfaces
        let sendDataModelSurfaces = surfaces.filter { $0.value.sendDataModel }
        guard !sendDataModelSurfaces.isEmpty else { return nil }

        var context: [String: AnyCodable] = [:]
        for (id, state) in sendDataModelSurfaces {
            context[id] = state.dataModel
        }

        guard let data = try? JSONEncoder().encode(context),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return "[A2UI Client Data Model] \(json)"
    }

    private static func applyMessage(
        _ message: ServerMessage,
        coordinator: SurfaceCoordinator,
        store: SurfaceStore
    ) async {
        do {
            try await coordinator.handle(message)
        } catch SurfaceCoordinator.CoordinatorError.surfaceAlreadyExists {
            if case .createSurface(let cs) = message {
                await store.deleteSurface(id: cs.surfaceId)
                try? await coordinator.handle(message)
            }
        } catch {
            // Non-fatal: log but don't crash the session
        }
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
