import Foundation
import LLMClient
import LLMTool
import LLMMCP
import UserNotifications

// MARK: - MacNotificationToolKit

/// macOS 通知を送信するツールを提供する ToolKit
///
/// `UNUserNotificationCenter` を使用して、macOS のバナー通知を送信します。
/// 初回使用時にユーザーに通知許可を要求します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     MacNotificationToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `send_notification`: macOS 通知を送信
/// - `list_pending_notifications`: 配信待ちの通知を一覧取得
public final class MacNotificationToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "notification"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            sendNotificationTool,
            listPendingNotificationsTool,
        ]
    }

    // MARK: - send_notification

    private var sendNotificationTool: BuiltInTool {
        BuiltInTool(
            name: "send_notification",
            description: """
                Send a macOS notification banner. Useful for alerting the user \
                about completed tasks, important events, or time-sensitive information. \
                Requires notification permission (requested automatically on first use).
                """,
            inputSchema: .object(
                properties: [
                    "title": .string(
                        description: "Notification title"
                    ),
                    "body": .string(
                        description: "Notification body text"
                    ),
                    "subtitle": .string(
                        description: "Optional subtitle shown below the title"
                    ),
                    "sound": .boolean(
                        description: "Play notification sound (default: true)"
                    ),
                    "identifier": .string(
                        description: "Unique identifier for the notification. Can be used to update or remove it later."
                    ),
                ],
                required: ["title", "body"]
            ),
            annotations: ToolAnnotations(
                title: "Send Notification",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(SendNotificationInput.self, from: data)

            let center = UNUserNotificationCenter.current()

            // 権限チェック・要求
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    return .error(
                        "Notification permission denied. "
                        + "Enable in System Settings > Notifications."
                    )
                }
            case .denied:
                return .error(
                    "Notification permission denied. "
                    + "Enable in System Settings > Notifications > [App Name]."
                )
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }

            // 通知コンテンツを作成
            let content = UNMutableNotificationContent()
            content.title = input.title
            content.body = input.body
            if let subtitle = input.subtitle {
                content.subtitle = subtitle
            }
            if input.sound ?? true {
                content.sound = .default
            }

            let identifier = input.identifier ?? UUID().uuidString
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil // 即時配信
            )

            try await center.add(request)

            return .text("Notification sent: \"\(input.title)\"")
        }
    }

    // MARK: - list_pending_notifications

    private var listPendingNotificationsTool: BuiltInTool {
        BuiltInTool(
            name: "list_pending_notifications",
            description: """
                List all pending (scheduled but not yet delivered) notifications.
                """,
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Pending Notifications",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()

            if pending.isEmpty {
                return .text("No pending notifications.")
            }

            var results: [PendingNotificationInfo] = []
            for request in pending {
                results.append(PendingNotificationInfo(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    subtitle: request.content.subtitle.isEmpty ? nil : request.content.subtitle
                ))
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return .text(json)
        }
    }
}

// MARK: - Input Types

private struct SendNotificationInput: Codable {
    var title: String
    var body: String
    var subtitle: String?
    var sound: Bool?
    var identifier: String?
}

// MARK: - Output Types

private struct PendingNotificationInfo: Codable {
    var identifier: String
    var title: String
    var body: String
    var subtitle: String?
}
