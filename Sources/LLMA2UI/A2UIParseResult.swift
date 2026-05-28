import A2UICore
import A2UIParser
import Foundation

enum A2UIParseResult: Sendable {
    case success([A2UIResponsePart])
    case failure(text: String, errors: [A2UIParseError])
}

enum A2UIResponseParser {
    static func parse(_ text: String) -> A2UIParseResult {
        let parts = A2UIBlockParser.parse(text)

        if parts.isEmpty {
            if text.contains(A2UIBlockParser.openTag) {
                return .failure(
                    text: text,
                    errors: [A2UIParseError(
                        blockIndex: 0,
                        rawJSON: "",
                        message: "Unclosed <a2ui-json> tag or malformed JSON inside it."
                    )]
                )
            }
            // No <a2ui-json> tags at all — but the LLM may have emitted bare ```json fences.
            if containsBareJSONFence(text) {
                return .failure(
                    text: text,
                    errors: [A2UIParseError(
                        blockIndex: 0,
                        rawJSON: "",
                        message: "Found bare ```json code fences but no <a2ui-json> tags. Every A2UI JSON block must be wrapped in <a2ui-json></a2ui-json> tags — markdown code fences are NOT recognized."
                    )]
                )
            }
            return .success([.text(text)])
        }

        let hasA2UIBlocks = parts.contains { $0.messages != nil }
        if !hasA2UIBlocks, text.contains(A2UIBlockParser.openTag) {
            return .failure(
                text: text,
                errors: [A2UIParseError(
                    blockIndex: 0,
                    rawJSON: "",
                    message: "Found <a2ui-json> tags but could not decode any valid A2UI messages (check the version field is \"v0.9\" and that each block contains one of: createSurface / updateComponents / updateDataModel / deleteSurface)."
                )]
            )
        }

        return .success(parts)
    }

    private static func containsBareJSONFence(_ text: String) -> Bool {
        // A bare ```json (or ``` followed by `{"version"` or `"createSurface"`) suggests the LLM
        // tried to emit A2UI JSON without the protocol's `<a2ui-json>` tags.
        if text.contains("```json") {
            return true
        }
        if text.contains("```") {
            return text.contains("\"version\"") || text.contains("\"createSurface\"") ||
                text.contains("\"updateComponents\"") || text.contains("\"updateDataModel\"")
        }
        return false
    }

    static func formatRetryPrompt(originalText: String, errors: [A2UIParseError]) -> String {
        var lines = [
            "Your previous response contained A2UI JSON blocks that failed to parse.",
            "Please regenerate the A2UI JSON blocks, fixing the following issues:",
            "",
        ]
        for error in errors {
            lines.append("- \(error.message)")
            if !error.rawJSON.isEmpty {
                let preview = String(error.rawJSON.prefix(200))
                lines.append("  Near: \(preview)")
            }
        }
        lines.append("")
        lines.append("Reminder of the required format:")
        lines.append("- Every A2UI JSON block MUST be wrapped in <a2ui-json>...</a2ui-json> tags.")
        lines.append("- Do NOT use markdown ```json code fences — those are ignored.")
        lines.append("- The JSON inside the tags must validate against the A2UI v0.9 schema.")
        lines.append("- A single block can contain a single message object OR an array of messages.")
        return lines.joined(separator: "\n")
    }
}
