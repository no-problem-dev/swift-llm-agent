import Foundation

/// 型消去された構造化出力の表示モデル
///
/// `StructuredProtocol` 型の出力を UI 層で扱えるように、
/// 型情報を文字列ベースに変換した表示専用モデル。
public struct StructuredResult: Sendable, Codable, Hashable {
    /// 元の型名（"AnalysisResult" 等）
    public let typeName: String

    /// 整形済み Markdown テキスト
    public let markdown: String

    /// 構造化セクション（見出し + 項目リスト）
    public let sections: [Section]

    /// メタデータ（confidence, qualityScore 等）
    public let metadata: [String: String]

    public struct Section: Sendable, Codable, Hashable {
        public let title: String
        public let items: [String]

        public init(title: String, items: [String]) {
            self.title = title
            self.items = items
        }
    }

    public init(
        typeName: String,
        markdown: String,
        sections: [Section] = [],
        metadata: [String: String] = [:]
    ) {
        self.typeName = typeName
        self.markdown = markdown
        self.sections = sections
        self.metadata = metadata
    }

    /// プレーンテキスト用ファクトリ
    public static func plainText(_ text: String) -> StructuredResult {
        StructuredResult(
            typeName: "PlainText",
            markdown: text
        )
    }
}
