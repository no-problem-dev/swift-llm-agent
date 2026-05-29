import A2UIPrompt
import A2UIPromptCompact
import LLMA2UI
import LLMClient

/// `A2UIChatSession` 用のプロンプト設定。
///
/// 内部で `A2UIPromptConfiguration` を構築し、append-only 運用に必要な調整を施す:
///
/// - `promptBuilder` に渡される schema の `allowedMessages` を
///   `["CreateSurfaceMessage", "UpdateComponentsMessage", "UpdateDataModelMessage"]` に固定
///   （`DeleteSurfaceMessage` を schema から除外）
/// - `workflowRules` 末尾に append-only 指示を自動追記
///
/// 利用側は `role` / `catalogSchema` / `workflowRules`(基底部) / `uiDescription` / `examples` を
/// 渡すだけで良く、LLM に伝える「append-only である」という contract は SDK が引き受ける。
public struct A2UIChatPromptConfiguration: Sendable {

    /// 標準的に schema へ残す message type 名（DeleteSurfaceMessage を除外したセット）。
    public static let allowedMessages: Set<String> = [
        "CreateSurfaceMessage",
        "UpdateComponentsMessage",
        "UpdateDataModelMessage",
    ]

    /// `workflowRules` 末尾に必ず付加される append-only 指示。
    public static let appendOnlyRules: String = """
    Append-only surfaces (chat-style UX):
    - Each turn MUST start with a `createSurface` for a NEW unique surfaceId.
    - You MUST NOT reference any surfaceId from earlier turns.
    - Within the current turn, `updateComponents` and `updateDataModel` are allowed only for the surface(s) you just created in this turn.
    - Do NOT emit `deleteSurface`.
    """

    public var role: String
    public var catalogSchema: String?
    public var workflowRules: String?
    public var uiDescription: String?
    public var examples: String?
    public var additionalSystemPrompt: SystemPrompt?

    /// `true` のとき `A2UIPromptCompactBuilder` (functions 抜きの最適化版) を内部で使う。
    /// catalog 側が `functions: []` なアプリで token を削れる。
    public var useCompactBuilder: Bool

    public init(
        role: String,
        catalogSchema: String? = nil,
        workflowRules: String? = nil,
        uiDescription: String? = nil,
        examples: String? = nil,
        additionalSystemPrompt: SystemPrompt? = nil,
        useCompactBuilder: Bool = false
    ) {
        self.role = role
        self.catalogSchema = catalogSchema
        self.workflowRules = workflowRules
        self.uiDescription = uiDescription
        self.examples = examples
        self.additionalSystemPrompt = additionalSystemPrompt
        self.useCompactBuilder = useCompactBuilder
    }

    // MARK: - Bridge to A2UIPromptConfiguration

    /// LLMA2UI が期待する `A2UIPromptConfiguration` に変換する。
    public func toUnderlying() -> A2UIPromptConfiguration {
        let builder: A2UIPromptBuilder = {
            if useCompactBuilder {
                let compact = A2UIPromptCompactBuilder(
                    catalogSchema: catalogSchema,
                    allowedMessages: Self.allowedMessages
                )
                return compact.builder
            } else {
                return A2UIPromptBuilder(
                    serverToClientSchema: nil,
                    commonTypesSchema: nil,
                    catalogSchema: catalogSchema,
                    allowedMessages: Self.allowedMessages,
                    pruneCommonTypes: true
                )
            }
        }()

        let combinedRules: String = {
            if let base = workflowRules, !base.isEmpty {
                return base + "\n\n" + Self.appendOnlyRules
            } else {
                return A2UIWorkflowRules.default + "\n\n" + Self.appendOnlyRules
            }
        }()

        return A2UIPromptConfiguration(
            role: role,
            promptBuilder: builder,
            workflowRules: combinedRules,
            uiDescription: uiDescription,
            examples: examples,
            additionalSystemPrompt: additionalSystemPrompt
        )
    }
}
