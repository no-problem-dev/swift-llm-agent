import Foundation

// MARK: - SkillMetadata

/// スキルの補足メタデータ
///
/// Agent Skills 標準のオプショナルフィールドを格納します。
public struct SkillMetadata: Sendable, Codable, Equatable {
    /// ライセンス（例: "MIT", "Apache-2.0"）
    public var license: String?

    /// 互換性情報（例: "Requires Python 3.10+"）
    public var compatibility: String?

    /// スキルのバージョン
    public var version: String?

    /// 作成者
    public var author: String?

    /// 分類タグ
    public var tags: [String]?

    /// 任意のキーバリューペア
    public var custom: [String: String]?

    public init(
        license: String? = nil,
        compatibility: String? = nil,
        version: String? = nil,
        author: String? = nil,
        tags: [String]? = nil,
        custom: [String: String]? = nil
    ) {
        self.license = license
        self.compatibility = compatibility
        self.version = version
        self.author = author
        self.tags = tags
        self.custom = custom
    }
}
