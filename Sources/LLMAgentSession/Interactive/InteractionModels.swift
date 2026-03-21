import Foundation

// MARK: - SelectionOption

/// 選択肢
public struct SelectionOption: Sendable, Codable, Identifiable {
    public let id: UUID
    public let label: String
    public let description: String?

    public init(
        id: UUID = UUID(),
        label: String,
        description: String? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
    }
}

// MARK: - ActionOption

/// アクションボタン
public struct ActionOption: Sendable, Codable, Identifiable {
    public let id: UUID
    public let label: String
    public let icon: String?
    public let style: ActionStyle
    public let message: String

    public init(
        id: UUID = UUID(),
        label: String,
        icon: String? = nil,
        style: ActionStyle = .standard,
        message: String
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.style = style
        self.message = message
    }

    /// アクションスタイル
    public enum ActionStyle: String, Sendable, Codable {
        case primary
        case standard
        case destructive
    }
}

// MARK: - QuickReplyOption

/// クイックリプライ
public struct QuickReplyOption: Sendable, Codable, Identifiable {
    public let id: UUID
    public let label: String
    public let icon: String?
    public let message: String

    public init(
        id: UUID = UUID(),
        label: String,
        icon: String? = nil,
        message: String
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.message = message
    }
}

// MARK: - ConfirmationDecision

/// 承認判断
public enum ConfirmationDecision: Sendable {
    /// 承認
    case approved

    /// 修正付き承認
    case modified(String)

    /// 却下
    case rejected
}
