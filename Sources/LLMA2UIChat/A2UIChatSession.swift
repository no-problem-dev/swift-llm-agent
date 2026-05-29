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
/// - サーフェスは毎ターン新規作成される。LLM が過去 surfaceId を再利用してきても
///   `SurfaceAppendHealer` が暗黙 fork で新 surface 化する
/// - `deleteSurface` は drop（過去メッセージはチャット履歴的に残す）
/// - プロンプトの schema から `DeleteSurfaceMessage` を除外、workflow rules に append-only 指示を追加
///
/// 履歴は完全な形（過去ターンの `<a2ui-json>` ブロック含む）で LLM に渡す。LLM が
/// 「過去ターンで何を表示済みか」を見える状態にしておくと、未表示の tool 結果を
/// 再利用するなどの自然な振る舞いになる。
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
        // historyProcessor は default の pass-through を使用する。
        // 履歴中の <a2ui-json> ブロックをそのまま LLM に見せることで、過去ターンで
        // 何を表示済みかという情報を LLM が保持できる（未表示の tool 結果を使い回せる）。
        // 「過去 surfaceId を再利用してしまう」リスクは AppendOnlyHealerAdapter の
        // 暗黙 fork が runtime 側で吸収するため、履歴側の防御は不要。
        self.underlying = A2UISession(
            client: client,
            model: model,
            tools: tools,
            messageProcessor: messageProcessor,
            promptConfiguration: promptConfiguration.toUnderlying(),
            agentConfiguration: agentConfiguration,
            a2uiConfiguration: a2uiConfiguration,
            serverMessageHealer: AppendOnlyHealerAdapter(defaultCatalogId: defaultCatalogId)
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

