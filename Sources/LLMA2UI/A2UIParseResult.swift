import A2UICore
import A2UIParser
import Foundation

enum A2UIParseResult: Sendable {
    case success([A2UIResponsePart])
    case failure(text: String, errors: [A2UIParseError])
}

struct A2UIParseError: Sendable {
    let blockIndex: Int
    let rawJSON: String
    let error: String
}

enum A2UIResponseParser {
    static func parse(_ text: String) -> A2UIParseResult {
        let parts = A2UIBlockParser.parse(text)

        if parts.isEmpty {
            if text.contains(A2UIBlockParser.openTag) {
                return .failure(
                    text: text,
                    errors: [A2UIParseError(blockIndex: 0, rawJSON: "", error: "Unclosed <a2ui-json> tag or malformed JSON")]
                )
            }
            return .success([.text(text)])
        }

        let hasA2UIBlocks = parts.contains { $0.messages != nil }
        if !hasA2UIBlocks && text.contains(A2UIBlockParser.openTag) {
            return .failure(
                text: text,
                errors: [A2UIParseError(blockIndex: 0, rawJSON: "", error: "Found <a2ui-json> tags but could not decode any valid A2UI messages")]
            )
        }

        return .success(parts)
    }

    static func formatRetryPrompt(originalText: String, errors: [A2UIParseError]) -> String {
        var lines = [
            "Your previous response contained A2UI JSON blocks that failed to parse.",
            "Please regenerate the A2UI JSON blocks, fixing the following issues:",
            ""
        ]
        for error in errors {
            lines.append("- \(error.error)")
            if !error.rawJSON.isEmpty {
                let preview = String(error.rawJSON.prefix(200))
                lines.append("  Near: \(preview)")
            }
        }
        lines.append("")
        lines.append("Remember: each A2UI JSON block must be wrapped in <a2ui-json></a2ui-json> tags and must validate against the A2UI v0.9 schema.")
        return lines.joined(separator: "\n")
    }
}
