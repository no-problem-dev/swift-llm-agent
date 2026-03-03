import Foundation

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

/// YAML フロントマターの軽量パーサー
///
/// SKILL.md / AGENT.md で使用される YAML のサブセットをパースします。
/// 外部依存なしで、以下の型をサポート:
/// - 文字列値
/// - 真偽値（true/false, yes/no）
/// - 文字列配列（`- item` 形式およびインライン `[a, b]` 形式）
/// - 複数行文字列（`|` リテラルブロック）
public enum FrontmatterParser {

    /// フロントマターと本文を分離してパース
    ///
    /// - Parameter content: YAML フロントマター + Markdown のテキスト
    /// - Returns: (フロントマター辞書, 本文)
    /// - Throws: フロントマターが見つからない場合
    public static func parse(_ content: String) throws -> ([String: Any], String) {
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

        let frontmatter = parseYAML(yamlContent)
        return (frontmatter, body)
    }

    // MARK: - Private

    /// 簡易 YAML パーサー
    private static func parseYAML(_ yaml: String) -> [String: Any] {
        var result: [String: Any] = [:]
        var currentKey: String? = nil
        var currentArray: [String]? = nil
        var multilineValue: String? = nil

        let lines = yaml.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 空行やコメントをスキップ
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                // マルチライン中は空行を保持
                if multilineValue != nil {
                    multilineValue? += "\n"
                }
                continue
            }

            // マルチライン値の継続（インデントされた行）
            if multilineValue != nil, let key = currentKey {
                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    multilineValue? += trimmedLine + "\n"
                    continue
                } else {
                    // マルチライン値の確定
                    result[key] = multilineValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                    multilineValue = nil
                    currentKey = nil
                }
            }

            // 配列アイテム（- value）
            if trimmedLine.hasPrefix("- "), let key = currentKey, multilineValue == nil {
                let value = String(trimmedLine.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if currentArray == nil {
                    currentArray = []
                }
                currentArray?.append(value)
                result[key] = currentArray
                continue
            }

            // 前の配列を確定
            if currentArray != nil {
                currentArray = nil
                currentKey = nil
            }

            // key: value ペア
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
                continue
            }

            let key = String(trimmedLine[trimmedLine.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // 次の行が配列かマルチラインかもしれない
                currentKey = key
                currentArray = nil
                continue
            }

            // マルチラインリテラルブロック（| または >）
            if rawValue == "|" || rawValue == ">" {
                currentKey = key
                multilineValue = ""
                continue
            }

            // インライン配列 [a, b, c]
            if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    .filter { !$0.isEmpty }
                result[key] = items
                currentKey = nil
                currentArray = nil
                continue
            }

            // 真偽値
            let lowerValue = rawValue.lowercased()
            if lowerValue == "true" || lowerValue == "yes" {
                result[key] = true
                currentKey = nil
                continue
            }
            if lowerValue == "false" || lowerValue == "no" {
                result[key] = false
                currentKey = nil
                continue
            }

            // 文字列値（クォート除去）
            let stringValue = rawValue
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[key] = stringValue
            currentKey = nil
        }

        // 末尾のマルチライン値を確定
        if let key = currentKey, let value = multilineValue {
            result[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}
