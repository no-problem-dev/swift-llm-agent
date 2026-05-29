import A2UICore
import A2UISurface
import LLMA2UI
import LLMAgent
import LLMClient
import LLMTool

/// チャット UX 向けの A2UI セッション。
///
/// `A2UISession` を内部に保持し、以下の append-only ポリシーを強制する:
///
/// - サーフェスは毎ターン新規作成される（過去 surface への変更は暗黙 fork で新 surface 化）
/// - `deleteSurface` は drop（過去メッセージはチャット履歴的に残す）
/// - `<a2ui-json>` ブロックは履歴に積む前に要約に置換（LLM の誤誘導防止）
/// - プロンプトの schema から `DeleteSurfaceMessage` を除外、workflow rules に append-only 指示を追加
///
/// 通常の `A2UISession` を直接置き換え可能な API を提供する。
@MainActor
public final class A2UIChatSession<Client: AgentCapableClient> where Client.Model: Sendable {

    private let underlying: A2UISession<Client>

    public var model: Client.Model {
        get { underlying.model }
        set { underlying.model = newValue }
    }

    public var agentConfiguration: AgentConfiguration {
        get { underlying.agentConfiguration }
        set { underlying.agentConfiguration = newValue }
    }

    public var messageProcessor: MessageProcessor {
        underlying.messageProcessor
    }

    public var conversationHistory: [LLMMessage] {
        underlying.conversationHistory
    }

    /// - Parameters:
    ///   - defaultCatalogId: 暗黙 fork で生成される `createSurface` の `catalogId`。
    ///     アプリの catalog id を渡す。
    public init(
        client: Client,
        model: Client.Model,
        tools: ToolSet = ToolSet {},
        messageProcessor: MessageProcessor = MessageProcessor(),
        promptConfiguration: A2UIChatPromptConfiguration,
        agentConfiguration: AgentConfiguration = .default,
        a2uiConfiguration: A2UIAgentConfiguration = .default,
        defaultCatalogId: String
    ) {
        self.underlying = A2UISession(
            client: client,
            model: model,
            tools: tools,
            messageProcessor: messageProcessor,
            promptConfiguration: promptConfiguration.toUnderlying(),
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration,
            serverMessageHealer: AppendOnlyHealerAdapter(defaultCatalogId: defaultCatalogId),
            historyProcessor: ChatHistoryProcessor()
        )
    }

    // MARK: - Public API (mirrors A2UISession)

    public func send(_ input: String) -> AsyncThrowingStream<A2UISessionStep, Error> {
        underlying.send(input)
    }

    public func handleAction(_ action: UserAction) -> AsyncThrowingStream<A2UISessionStep, Error> {
        underlying.handleAction(action)
    }

    public func reset() {
        underlying.reset()
    }
}

// MARK: - Adapters

/// `SurfaceAppendHealer` を `A2UIServerMessageHealer` に適合させるアダプタ。
private struct AppendOnlyHealerAdapter: A2UIServerMessageHealer {
    let defaultCatalogId: String

    func heal(_ messages: [ServerMessage], existing: Set<String>) -> [ServerMessage] {
        SurfaceAppendHealer.heal(
            messages,
            lockedIds: existing,
            defaultCatalogId: defaultCatalogId
        )
    }
}

/// `ChatHistorySanitizer` を `A2UIHistoryProcessor` に適合させるアダプタ。
private struct ChatHistoryProcessor: A2UIHistoryProcessor {
    func process(_ messages: [LLMMessage]) -> [LLMMessage] {
        ChatHistorySanitizer.sanitize(messages)
    }
}
