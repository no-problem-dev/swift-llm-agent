import Foundation
import LLMAgent

/// プロジェクト値型
///
/// セッション横断のナレッジ・カスタム指示を束ねるコンテナ。
/// Claude Projects の「プロジェクト」に相当する。
public struct Project: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var iconName: String
    public var configuration: ProjectConfiguration
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        iconName: String = "folder.fill",
        configuration: ProjectConfiguration = ProjectConfiguration(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
