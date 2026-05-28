import A2UIPrompt
import LLMClient

/// Configures how the A2UI system prompt is assembled for `runA2UIAgent` / `A2UISession`.
///
/// By default this reproduces the canonical A2UI prompt over the bundled basic catalog.
/// Callers with a **custom component catalog** (extra components, custom workflow / UI guidance)
/// supply a configured `A2UIPromptBuilder` plus optional `workflowRules` / `uiDescription`, so the
/// schema block reflects their catalog — without the caller having to re-assemble (and risk
/// duplicating) the A2UI schema in an `additionalSystemPrompt`.
public struct A2UIPromptConfiguration: Sendable {
    public var role: String
    public var promptBuilder: A2UIPromptBuilder
    public var workflowRules: String?
    public var uiDescription: String?
    public var examples: String?
    public var additionalSystemPrompt: SystemPrompt?

    public init(
        role: String = "You are a helpful assistant that generates A2UI interfaces.",
        promptBuilder: A2UIPromptBuilder = A2UIPromptBuilder(),
        workflowRules: String? = nil,
        uiDescription: String? = nil,
        examples: String? = nil,
        additionalSystemPrompt: SystemPrompt? = nil
    ) {
        self.role = role
        self.promptBuilder = promptBuilder
        self.workflowRules = workflowRules
        self.uiDescription = uiDescription
        self.examples = examples
        self.additionalSystemPrompt = additionalSystemPrompt
    }

    public static let `default` = A2UIPromptConfiguration()

    func makeSystemPrompt() -> SystemPrompt {
        let a2uiPrompt = promptBuilder.buildSystemPrompt(
            role: role,
            workflowRules: workflowRules,
            uiDescription: uiDescription,
            examples: examples
        )
        var full = SystemPrompt {
            PromptComponent.context(a2uiPrompt)
        }
        if let additional = additionalSystemPrompt {
            full = full + additional
        }
        return full
    }
}
