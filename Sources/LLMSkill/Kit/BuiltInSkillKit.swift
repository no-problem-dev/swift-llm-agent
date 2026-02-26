import Foundation
import LLMAgent

// MARK: - BuiltInSkillKit

/// 汎用的なビルトインスキルキット
///
/// どのアプリケーションでも使える汎用スキルを提供します。
///
/// - `summarize`: テキスト要約（fork モード）
/// - `code-review`: コードレビュー（fork モード）
///
/// ## 使用例
///
/// ```swift
/// let registry = SkillRegistryDefinition {
///     BuiltInSkillKit()
/// }
///
/// let tool = SkillTool(
///     client: client, model: model,
///     registry: registry
/// )
/// ```
public struct BuiltInSkillKit: SkillKit {
    public let name = "built-in"
    public let skills: [any AgentSkill]

    public init() {
        self.skills = [
            Self.summarizeSkill,
            Self.codeReviewSkill,
        ]
    }

    // MARK: - Summarize Skill

    private static var summarizeSkill: AgentSkillDefinition {
        AgentSkillDefinition(
            name: "summarize",
            description: "Summarizes text or content concisely",
            executionMode: .fork,
            instructions: """
                # Summarization Instructions

                When summarizing content, follow these guidelines:

                1. **Read the entire content** before starting to summarize
                2. **Identify key points** - main arguments, conclusions, and supporting evidence
                3. **Structure the summary**:
                   - Start with a one-sentence overview
                   - List 3-5 key points as bullet points
                   - End with the main takeaway or conclusion
                4. **Preserve accuracy** - do not add information not in the original
                5. **Maintain the original tone** - formal content gets formal summary
                6. **Target length**: approximately 20-30% of the original length

                If the user specifies a target length or format, prioritize their request.
                Always respond in the same language as the input content.
                """,
            configuration: AgentConfiguration(maxSteps: 3),
            metadata: SkillMetadata(
                version: "1.0.0",
                author: "BuiltInSkillKit",
                tags: ["text", "summarization", "universal"]
            )
        )
    }

    // MARK: - Code Review Skill

    private static var codeReviewSkill: AgentSkillDefinition {
        AgentSkillDefinition(
            name: "code-review",
            description: "Reviews code for quality, security, and best practices",
            executionMode: .fork,
            instructions: """
                # Code Review Instructions

                You are a code review specialist. Analyze the provided code thoroughly.

                ## Review Checklist

                1. **Correctness**: Logic errors, edge cases, off-by-one errors
                2. **Security**: Input validation, injection risks, data exposure
                3. **Performance**: Unnecessary allocations, N+1 queries, blocking calls
                4. **Readability**: Naming conventions, code organization, documentation
                5. **Maintainability**: DRY violations, coupling, testability

                ## Output Format

                Provide your review as:
                - **Summary**: One paragraph overall assessment
                - **Issues Found**: Categorized list (Critical / Warning / Suggestion)
                - **Positive Aspects**: What the code does well
                - **Recommendations**: Top 3 actionable improvements

                Be constructive and specific. Reference line numbers or code snippets when possible.
                Always respond in Japanese.
                """,
            configuration: AgentConfiguration(maxSteps: 8),
            metadata: SkillMetadata(
                version: "1.0.0",
                author: "BuiltInSkillKit",
                tags: ["code", "review", "quality"]
            )
        )
    }
}
