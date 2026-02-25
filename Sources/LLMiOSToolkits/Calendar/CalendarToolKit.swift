@preconcurrency import EventKit
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - CalendarToolKit

/// カレンダーとリマインダーを操作する ToolKit
///
/// EventKit を使用して、カレンダーイベントの検索・作成、
/// リマインダーの検索・作成を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     CalendarToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `list_calendars`: カレンダー/リマインダーリスト一覧を取得
/// - `search_events`: 日付範囲やキーワードでイベントを検索
/// - `create_event`: 新しいカレンダーイベントを作成
/// - `search_reminders`: リマインダーを検索
/// - `create_reminder`: 新しいリマインダーを作成
public final class CalendarToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "calendar"

    private let eventStore: EKEventStore
    private let eventGuard: PermissionGuard
    private let reminderGuard: PermissionGuard

    // MARK: - Initialization

    /// CalendarToolKit を作成
    ///
    /// - Parameter eventStore: 使用する EKEventStore（デフォルトは新規インスタンス）
    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.eventGuard = PermissionGuard(
            provider: CalendarEventPermission(eventStore: eventStore)
        )
        self.reminderGuard = PermissionGuard(
            provider: CalendarReminderPermission(eventStore: eventStore)
        )
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            listCalendarsTool,
            searchEventsTool,
            createEventTool,
            searchRemindersTool,
            createReminderTool,
        ]
    }

    // MARK: - list_calendars

    private var listCalendarsTool: BuiltInTool {
        BuiltInTool(
            name: "list_calendars",
            description: "List all available calendars and reminder lists. "
                + "Use this to discover calendar IDs before searching or creating events.",
            inputSchema: .object(
                properties: [
                    "type": .string(
                        description: "Filter by type: 'event', 'reminder', or 'all' (default: 'all')"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Calendars",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [eventStore, eventGuard, reminderGuard] data in
            let input = try JSONDecoder().decode(ListCalendarsInput.self, from: data)
            let type = input.type?.lowercased() ?? "all"

            var calendars: [CalendarInfo] = []

            if type == "all" || type == "event" {
                if let error = await eventGuard.ensureAuthorized() { return error }
                calendars += eventStore.calendars(for: .event).map {
                    CalendarInfo(from: $0, type: "event")
                }
            }
            if type == "all" || type == "reminder" {
                if let error = await reminderGuard.ensureAuthorized() { return error }
                calendars += eventStore.calendars(for: .reminder).map {
                    CalendarInfo(from: $0, type: "reminder")
                }
            }

            return try .encoded(calendars)
        }
    }

    // MARK: - search_events

    private var searchEventsTool: BuiltInTool {
        BuiltInTool(
            name: "search_events",
            description: "Search calendar events by date range and optional keyword. "
                + "Returns matching events with title, dates, location, and notes. "
                + "Date range is required; use list_calendars first to get calendar IDs if needed. "
                + "IMPORTANT: Use the user's local time, not UTC. Dates without timezone offset are treated as local time.",
            inputSchema: .object(
                properties: [
                    "start_date": .string(
                        description: "Start of date range in ISO8601 format with timezone offset (e.g., '2025-03-15T00:00:00+09:00') or without timezone for local time (e.g., '2025-03-15T00:00:00'). Do NOT use 'Z' (UTC) unless the user explicitly requests UTC."
                    ),
                    "end_date": .string(
                        description: "End of date range in ISO8601 format with timezone offset or without timezone for local time"
                    ),
                    "keyword": .string(
                        description: "Optional keyword to filter events by title, notes, or location"
                    ),
                    "calendar_ids": .array(
                        description: "Optional array of calendar IDs to search in (searches all if omitted)",
                        items: .string()
                    ),
                    "limit": .integer(
                        description: "Maximum number of events to return (default: 50, max: 200)"
                    ),
                ],
                required: ["start_date", "end_date"]
            ),
            annotations: ToolAnnotations(
                title: "Search Events",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [eventStore, eventGuard] data in
            if let error = await eventGuard.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SearchEventsInput.self, from: data)

            guard let start = CalendarDateHelper.parseDate(input.startDate) else {
                return .error("Invalid start_date format. Use ISO8601 with timezone (e.g., '2025-03-15T00:00:00+09:00') or local time (e.g., '2025-03-15T00:00:00').")
            }
            guard let end = CalendarDateHelper.parseDate(input.endDate) else {
                return .error("Invalid end_date format. Use ISO8601 with timezone (e.g., '2025-03-15T23:59:59+09:00') or local time (e.g., '2025-03-15T23:59:59').")
            }

            let calendars: [EKCalendar]?
            if let ids = input.calendarIds, !ids.isEmpty {
                calendars = ids.compactMap { eventStore.calendar(withIdentifier: $0) }
                if calendars?.isEmpty == true {
                    return .error("No valid calendars found for the given IDs. Use list_calendars to get valid IDs.")
                }
            } else {
                calendars = nil
            }

            let predicate = eventStore.predicateForEvents(
                withStart: start, end: end, calendars: calendars
            )
            let limit = min(input.limit ?? 50, 200)
            var events = eventStore.events(matching: predicate).map { EventInfo(from: $0) }

            // キーワードフィルタリング
            if let keyword = input.keyword?.lowercased(), !keyword.isEmpty {
                events = events.filter {
                    $0.title.lowercased().contains(keyword)
                        || ($0.notes?.lowercased().contains(keyword) ?? false)
                        || ($0.location?.lowercased().contains(keyword) ?? false)
                }
            }

            let result = Array(events.prefix(limit))
            return try .encoded(result)
        }
    }

    // MARK: - create_event

    private var createEventTool: BuiltInTool {
        BuiltInTool(
            name: "create_event",
            description: "Create a new calendar event. Returns the created event details including its ID. "
                + "IMPORTANT: Use the user's local time, not UTC. Dates without timezone offset are treated as local time.",
            inputSchema: .object(
                properties: [
                    "title": .string(description: "Event title"),
                    "start_date": .string(description: "Start date in ISO8601 format with timezone offset (e.g., '2025-03-15T10:00:00+09:00') or without timezone for local time (e.g., '2025-03-15T10:00:00')"),
                    "end_date": .string(description: "End date in ISO8601 format with timezone offset or without timezone for local time"),
                    "calendar_id": .string(
                        description: "Calendar ID to create the event in (uses default calendar if omitted)"
                    ),
                    "notes": .string(description: "Event notes/description"),
                    "location": .string(description: "Event location"),
                    "is_all_day": .boolean(description: "Whether this is an all-day event (default: false)"),
                    "url": .string(description: "URL associated with the event"),
                ],
                required: ["title", "start_date", "end_date"]
            ),
            annotations: ToolAnnotations(
                title: "Create Event",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { [eventStore, eventGuard] data in
            if let error = await eventGuard.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(CreateEventInput.self, from: data)

            guard let start = CalendarDateHelper.parseDate(input.startDate) else {
                return .error("Invalid start_date format. Use ISO8601 with timezone (e.g., '2025-03-15T10:00:00+09:00') or local time (e.g., '2025-03-15T10:00:00').")
            }
            guard let end = CalendarDateHelper.parseDate(input.endDate) else {
                return .error("Invalid end_date format. Use ISO8601 with timezone (e.g., '2025-03-15T11:00:00+09:00') or local time (e.g., '2025-03-15T11:00:00').")
            }

            let event = EKEvent(eventStore: eventStore)
            event.title = input.title
            event.startDate = start
            event.endDate = end
            event.isAllDay = input.isAllDay ?? false
            event.notes = input.notes
            event.location = input.location

            if let urlString = input.url, let url = URL(string: urlString) {
                event.url = url
            }

            if let calendarId = input.calendarId,
               let calendar = eventStore.calendar(withIdentifier: calendarId) {
                event.calendar = calendar
            } else {
                event.calendar = eventStore.defaultCalendarForNewEvents
            }

            do {
                try eventStore.save(event, span: .thisEvent)
                return try .encoded(EventInfo(from: event))
            } catch {
                return .error("Failed to create event: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - search_reminders

    private var searchRemindersTool: BuiltInTool {
        BuiltInTool(
            name: "search_reminders",
            description: "Search reminders. Can filter by completion status, keyword, and reminder list. "
                + "Returns matching reminders with title, due date, priority, and completion status.",
            inputSchema: .object(
                properties: [
                    "completed": .boolean(
                        description: "Filter by completion: true (completed only), false (incomplete only). Omit for all."
                    ),
                    "keyword": .string(description: "Optional keyword to filter by title or notes"),
                    "calendar_ids": .array(
                        description: "Optional reminder list IDs to search in",
                        items: .string()
                    ),
                    "limit": .integer(description: "Maximum results to return (default: 50, max: 200)"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Search Reminders",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [eventStore, reminderGuard] data in
            if let error = await reminderGuard.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(SearchRemindersInput.self, from: data)

            let calendars: [EKCalendar]?
            if let ids = input.calendarIds, !ids.isEmpty {
                calendars = ids.compactMap { eventStore.calendar(withIdentifier: $0) }
            } else {
                calendars = nil
            }

            // 完了状態に応じた predicate を選択
            let predicate: NSPredicate
            if let completed = input.completed {
                if completed {
                    predicate = eventStore.predicateForCompletedReminders(
                        withCompletionDateStarting: nil, ending: nil, calendars: calendars
                    )
                } else {
                    predicate = eventStore.predicateForIncompleteReminders(
                        withDueDateStarting: nil, ending: nil, calendars: calendars
                    )
                }
            } else {
                predicate = eventStore.predicateForReminders(in: calendars)
            }

            // fetchReminders は completion ベースなので async でラップ
            // EKReminder は non-Sendable のため、completion 内で Sendable な ReminderInfo に変換
            let limit = min(input.limit ?? 50, 200)
            var results: [ReminderInfo] = try await withCheckedThrowingContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { result in
                    let infos = (result ?? []).map { ReminderInfo(from: $0) }
                    continuation.resume(returning: infos)
                }
            }

            // キーワードフィルタリング
            if let keyword = input.keyword?.lowercased(), !keyword.isEmpty {
                results = results.filter {
                    $0.title.lowercased().contains(keyword)
                        || ($0.notes?.lowercased().contains(keyword) ?? false)
                }
            }

            return try .encoded(Array(results.prefix(limit)))
        }
    }

    // MARK: - create_reminder

    private var createReminderTool: BuiltInTool {
        BuiltInTool(
            name: "create_reminder",
            description: "Create a new reminder. Returns the created reminder details including its ID. "
                + "IMPORTANT: Use the user's local time, not UTC.",
            inputSchema: .object(
                properties: [
                    "title": .string(description: "Reminder title"),
                    "calendar_id": .string(
                        description: "Reminder list ID (uses default list if omitted)"
                    ),
                    "due_date": .string(description: "Due date in ISO8601 format with timezone offset (e.g., '2025-03-15T10:00:00+09:00') or without timezone for local time (e.g., '2025-03-15T10:00:00')"),
                    "notes": .string(description: "Reminder notes"),
                    "priority": .integer(
                        description: "Priority: 0 (none), 1 (high), 5 (medium), 9 (low)"
                    ),
                ],
                required: ["title"]
            ),
            annotations: ToolAnnotations(
                title: "Create Reminder",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ) { [eventStore, reminderGuard] data in
            if let error = await reminderGuard.ensureAuthorized() { return error }

            let input = try JSONDecoder().decode(CreateReminderInput.self, from: data)

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = input.title
            reminder.notes = input.notes
            reminder.priority = input.priority ?? 0

            if let dueDateString = input.dueDate,
               let dueDate = CalendarDateHelper.parseDate(dueDateString) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: dueDate
                )
            }

            if let calendarId = input.calendarId,
               let calendar = eventStore.calendar(withIdentifier: calendarId) {
                reminder.calendar = calendar
            } else {
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
            }

            do {
                try eventStore.save(reminder, commit: true)
                return try .encoded(ReminderInfo(from: reminder))
            } catch {
                return .error("Failed to create reminder: \(error.localizedDescription)")
            }
        }
    }
}
