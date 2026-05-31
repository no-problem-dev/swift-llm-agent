import Foundation
import StructuredDataCore
import YAMLParsing

// MARK: - FrontmatterParseError

/// フロントマターパース時のエラー
public enum FrontmatterParseError: Error, Sendable, LocalizedError {
    /// 開始デリミタ（---）が見つからない
    case missingOpeningDelimiter
    /// 終了デリミタ（---）が見つからない
    case missingClosingDelimiter

    public var errorDescription: String? {
        switch self {
        case .missingOpeningDelimiter:
            "Missing YAML frontmatter delimiter (---)"
        case .missingClosingDelimiter:
            "Missing closing frontmatter delimiter (---)"
        }
    }
}

// MARK: - FrontmatterParser

/// Markdown フロントマター（`---` 区切り）の分離器。
///
/// SKILL.md / AGENT.md の先頭 YAML ブロックと本文を切り出し、YAML 本体の解釈は
/// structured-data の ``YAMLParser``（YAML 1.2 Core）へ委譲する。スカラの型付け
/// （真偽値・数値・null・文字列）は YAML 仕様に従う。
public enum FrontmatterParser {

    /// フロントマターと本文を分離してパース
    ///
    /// - Parameter content: YAML フロントマター + Markdown のテキスト
    /// - Returns: (フロントマター, 本文)
    /// - Throws: フロントマターが見つからない場合
    public static func parse(_ content: String) throws -> (StructuredValue, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("---") else {
            throw FrontmatterParseError.missingOpeningDelimiter
        }

        // 開始 --- の後の行から、次の --- を探す
        let afterStart = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let remaining = String(trimmed[afterStart...])

        guard let endRange = remaining.range(of: "\n---") else {
            throw FrontmatterParseError.missingClosingDelimiter
        }

        let yamlContent = String(remaining[remaining.startIndex..<endRange.lowerBound])

        // --- の後に改行があればスキップ
        var bodyStart = endRange.upperBound
        if bodyStart < remaining.endIndex {
            let nextChar = remaining[bodyStart]
            if nextChar == "\n" {
                bodyStart = remaining.index(after: bodyStart)
            }
        }
        let body = bodyStart < remaining.endIndex
            ? String(remaining[bodyStart...])
            : ""

        let frontmatter = (try? YAMLParser().parse(yamlContent)) ?? .object(OrderedObject())
        return (frontmatter, body)
    }

}
