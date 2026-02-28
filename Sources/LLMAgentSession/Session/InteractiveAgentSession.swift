import Foundation
import LLMClient
import LLMTool

// MARK: - InteractiveAgentSession

/// インタラクティブエージェントセッション
///
/// `ChatSession` をラップし、Layer 1（InteractiveTool）と
/// Layer 2（DirectiveGenerator）を統合する。
///
/// ## 2 層アーキテクチャ
///
/// - **Layer 1**: 実行中の InteractiveTool によるインタラクション
///   → `ChatSession` が直接処理（`awaitingInteraction` イベント）
/// - **Layer 2**: 完了後の DirectiveGenerator によるインタラクション提案
///   → このクラスが `.completed` を検出し、`directive` イベントに変換
///
/// ## 状態遷移
///
/// ```
/// send() → running → ... → completed(result)
///   ├─ directive あり → directive(result, request)
///   │   ├─ respond(.action(msg)) → send(msg) → running (新ターン)
///   │   └─ respond(.dismissed) → completed
///   └─ directive なし → completed
/// ```
///
/// ## 使用例
///
/// ```swift
/// let session = InteractiveAgentSession(
///     chatSession: chatSession,
///     directiveGenerator: RuleBasedDirectiveGenerator()
/// )
///
/// for try await event in await session.send("調査して") {
///     switch event {
///     case .directive(let result, let request):
///         // ディレクティブ UI を表示
///         InteractionView(request: request) { response in
///             Task { await session.respond(response) }
///         }
///     case .completed(let result):
///         // 通常の完了処理
///     default: break
///     }
/// }
/// ```
public actor InteractiveAgentSession<Client: AgentCapableClient>: ChatSessionProtocol
    where Client.Model: Sendable
{
    // MARK: - Properties

    private let inner: ChatSession<Client>

    /// ディレクティブ生成器（Layer 2）
    public var directiveGenerator: (any DirectiveGenerator)?

    /// 完了時の結果（ディレクティブ待機中に保持）
    private var pendingDirectiveResult: StructuredResult?

    /// ディレクティブ応答待機用の continuation
    private var directiveContinuation: CheckedContinuation<InteractionResponse, Never>?

    // MARK: - Initialization

    public init(
        chatSession: ChatSession<Client>,
        directiveGenerator: (any DirectiveGenerator)? = nil
    ) {
        self.inner = chatSession
        self.directiveGenerator = directiveGenerator
    }

    // MARK: - ChatSessionProtocol: Core Operations

    public func send(_ text: String) async -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let innerStream = await inner.send(text)
        return wrapWithDirective(innerStream)
    }

    public func resume() async -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let innerStream = await inner.resume()
        return wrapWithDirective(innerStream)
    }

    public func respond(_ response: InteractionResponse) async {
        // ディレクティブ待機中の場合
        if let continuation = directiveContinuation {
            directiveContinuation = nil
            continuation.resume(returning: response)
            return
        }

        // Layer 1: inner session にフォワード
        await inner.respond(response)
    }

    public func interrupt(_ message: String) async {
        await inner.interrupt(message)
    }

    public func cancel() async {
        pendingDirectiveResult = nil
        if let continuation = directiveContinuation {
            directiveContinuation = nil
            continuation.resume(returning: InteractionResponse(
                requestId: "",
                content: .dismissed
            ))
        }
        await inner.cancel()
    }

    public func clear() async {
        pendingDirectiveResult = nil
        await inner.clear()
    }

    public func getSerializedMessages() async -> Data? {
        await inner.getSerializedMessages()
    }

    // MARK: - ChatSessionProtocol: Turn Configuration

    public var turnConfiguration: TurnConfiguration {
        get async { await inner.turnConfiguration }
    }

    public func setTurnConfiguration(_ config: TurnConfiguration) async {
        await inner.setTurnConfiguration(config)
    }

    // MARK: - ChatSessionProtocol: Model Selection

    public var currentModelId: String {
        get async { await inner.currentModelId }
    }

    public var registeredModelIds: [String] {
        get async { await inner.registeredModelIds }
    }

    public func selectModel(id: String) async {
        await inner.selectModel(id: id)
    }

    // MARK: - ChatSessionProtocol: Output Type Selection

    public var currentOutputTypeId: String {
        get async { await inner.currentOutputTypeId }
    }

    public var registeredOutputTypeIds: [String] {
        get async { await inner.registeredOutputTypeIds }
    }

    public func selectOutputType(id: String) async {
        await inner.selectOutputType(id: id)
    }

    // MARK: - Registration (Convenience)

    public func registerModel(id: String, model: Client.Model) async {
        await inner.registerModel(id: id, model: model)
    }

    public func registerOutputType<Output: StructuredProtocol>(
        id: String,
        type: Output.Type,
        render: @Sendable @escaping (Output) -> StructuredResult
    ) async {
        await inner.registerOutputType(id: id, type: type, render: render)
    }

    public func registerOutputType<Output: StructuredProtocol & StructuredOutputRenderable>(
        id: String,
        type: Output.Type
    ) async {
        await inner.registerOutputType(id: id, type: type)
    }

    // MARK: - Private: Stream Transformation

    private func wrapWithDirective(
        _ stream: AsyncThrowingStream<SessionPhaseEvent, Error>
    ) -> AsyncThrowingStream<SessionPhaseEvent, Error> {
        let generator = directiveGenerator

        // generator がない場合はそのまま返す
        guard generator != nil else { return stream }

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    for try await event in stream {
                        if Task.isCancelled { break }

                        if case .completed(let result) = event,
                           let self = self
                        {
                            // Layer 2: DirectiveGenerator を実行
                            await self.handleCompleted(
                                result: result,
                                generator: generator!,
                                continuation: continuation
                            )
                        } else {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func handleCompleted(
        result: StructuredResult,
        generator: any DirectiveGenerator,
        continuation: AsyncThrowingStream<SessionPhaseEvent, Error>.Continuation
    ) async {
        // DirectiveGenerator でインタラクション提案を生成
        let directive: InteractionRequest?
        do {
            directive = try await generator.generate(from: result)
        } catch {
            // 生成失敗時は通常の completed として返す
            continuation.yield(.completed(result: result))
            return
        }

        guard let request = directive else {
            // directive なし → 通常の completed
            continuation.yield(.completed(result: result))
            return
        }

        // directive あり → directive イベントを発行して応答を待機
        pendingDirectiveResult = result
        continuation.yield(.directive(result: result, request: request))

        // ユーザーの応答を待機
        let response = await withCheckedContinuation { cont in
            self.directiveContinuation = cont
        }

        pendingDirectiveResult = nil

        switch response.content {
        case .action(let message):
            // アクション選択 → 新ターンを開始
            let newStream = await inner.send(message)
            do {
                for try await event in newStream {
                    if Task.isCancelled { break }

                    if case .completed(let newResult) = event {
                        // 再帰的にディレクティブ生成
                        await handleCompleted(
                            result: newResult,
                            generator: generator,
                            continuation: continuation
                        )
                    } else {
                        continuation.yield(event)
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        case .dismissed:
            // 却下 → 通常の completed
            continuation.yield(.completed(result: result))
        case .text(let text) where !text.isEmpty:
            // テキスト入力 → 新ターンを開始
            let newStream = await inner.send(text)
            do {
                for try await event in newStream {
                    if Task.isCancelled { break }

                    if case .completed(let newResult) = event {
                        await handleCompleted(
                            result: newResult,
                            generator: generator,
                            continuation: continuation
                        )
                    } else {
                        continuation.yield(event)
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        default:
            // その他 → 通常の completed
            continuation.yield(.completed(result: result))
        }
    }
}
