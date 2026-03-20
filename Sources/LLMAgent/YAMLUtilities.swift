import Foundation

// MARK: - YAML Utilities

/// YAML の値をエスケープする
///
/// 特殊文字（コロン、ダブルクォート、改行、ハッシュ、シングルクォート）を含む場合、
/// 値をダブルクォートで囲み、内部のバックスラッシュとダブルクォートをエスケープする。
package func yamlQuote(_ value: String) -> String {
    guard value.contains(":") || value.contains("\"") || value.contains("\n") || value.contains("#") || value.contains("'") else {
        return value
    }
    return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
}
