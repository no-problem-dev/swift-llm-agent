import Foundation
import LLMClient
import LLMTool
import LLMMCP
import UserNotifications

// MARK: - NotificationToolKit

/// ローカル通知を操作する ToolKit
///
/// UserNotifications framework を使用して、
/// 通知のスケジュール・一覧取得・キャンセルを提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     NotificationToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `schedule_notification`: ローカル通知をスケジュール
/// - `list_pending_notifications`: 予定済み通知の一覧
/// - `cancel_notification`: 通知のキャンセル
public final class NotificationToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "notification"

    private let guard_: PermissionGuard

    // MARK: - Initialization

    public init() {
        self.guard_ = PermissionGuard(
            provider: NotificationPermission()
        )
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            scheduleNotificationTool,
            listPendingNotificationsTool,
            cancelNotificationTool,
        ]
    }

    // MARK: - schedule_notification

    private var scheduleNotificationTool: BuiltInTool {
        BuiltInTool(
            name: "schedule_notification",
            description: "Schedule a local notification. Specify either a specific date/time or a delay in seconds. "
                + "IMPORTANT: Use the user's local time for dates.",
            inputSchema: .object(
                properties: [
                    "title": .string(description: "Notification title"),
                    "body": .string(description: "Notification body text"),
                    "date": .string(
                        description: "Notification date in ISO8601 format (e.g., '2025-03-15T10:00:00+09:00'). "
                            + "Use this OR delay_seconds, not both."
                    ),
                    "delay_seconds": .number(
                        description: "Delay in seconds from now (e.g., 1800 for 30 minutes). "
                            + "Use this OR date, not both."
                    ),
                    "identifier": .string(
                        description: "Unique identifier for the notification (auto-generated if omitted). "
                            + "Use this to cancel the notification later."
                    ),
                ],
                required: ["title"]
            ),
            annotations: ToolAnnotations(
                title: "Schedule Notification",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(ScheduleNotificationInput.self, from: data)

            let content = UNMutableNotificationContent()
            content.title = input.title
            content.body = input.body ?? ""
            content.sound = .default

            let trigger: UNNotificationTrigger
            var triggerDate: String?
            var triggerDelay: Double?

            if let dateString = input.date {
                guard let date = CalendarDateHelper.parseDate(dateString) else {
                    return .error(
                        "Invalid date format. Use ISO8601 (e.g., '2025-03-15T10:00:00+09:00')."
                    )
                }
                guard date > Date() else {
                    return .error("Notification date must be in the future.")
                }
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: date
                )
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
                triggerDate = CalendarDateHelper.formatDate(date)
            } else if let delay = input.delaySeconds {
                guard delay > 0 else {
                    return .error("delay_seconds must be positive.")
                }
                trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: delay,
                    repeats: false
                )
                triggerDelay = delay
            } else {
                return .error(
                    "Either 'date' or 'delay_seconds' must be specified."
                )
            }

            let identifier = input.identifier ?? UUID().uuidString
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                let info = NotificationInfo(
                    identifier: identifier,
                    title: input.title,
                    body: input.body,
                    triggerDate: triggerDate,
                    triggerDelay: triggerDelay
                )
                return try .encoded(info)
            } catch {
                return .error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - list_pending_notifications

    private var listPendingNotificationsTool: BuiltInTool {
        BuiltInTool(
            name: "list_pending_notifications",
            description: "List all pending (scheduled but not yet delivered) notifications.",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Pending Notifications",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let requests = await UNUserNotificationCenter.current()
                .pendingNotificationRequests()

            let infos: [NotificationInfo] = requests.map { request in
                var triggerDate: String?
                var triggerDelay: Double?

                if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
                    if let date = Calendar.current.date(from: calendarTrigger.dateComponents) {
                        triggerDate = CalendarDateHelper.formatDate(date)
                    }
                } else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                    triggerDelay = intervalTrigger.timeInterval
                }

                return NotificationInfo(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body.isEmpty ? nil : request.content.body,
                    triggerDate: triggerDate,
                    triggerDelay: triggerDelay
                )
            }

            return try .encoded(infos)
        }
    }

    // MARK: - cancel_notification

    private var cancelNotificationTool: BuiltInTool {
        BuiltInTool(
            name: "cancel_notification",
            description: "Cancel a pending notification by its identifier. "
                + "Use list_pending_notifications first to find the identifier.",
            inputSchema: .object(
                properties: [
                    "identifier": .string(
                        description: "Notification identifier to cancel"
                    ),
                ],
                required: ["identifier"]
            ),
            annotations: ToolAnnotations(
                title: "Cancel Notification",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [guard_] data in
            if let error = await guard_.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(CancelNotificationInput.self, from: data)

            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [input.identifier])

            return .text("Notification '\(input.identifier)' has been cancelled.")
        }
    }
}
