@preconcurrency import EventKit
import Foundation

// MARK: - Input Types

struct ListCalendarsInput: Codable {
    var type: String?
}

struct SearchEventsInput: Codable {
    var startDate: String
    var endDate: String
    var keyword: String?
    var calendarIds: [String]?
    var scope: String?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case keyword
        case calendarIds = "calendar_ids"
        case scope
        case limit
    }
}

struct CreateEventInput: Codable {
    var title: String
    var startDate: String
    var endDate: String
    var calendarId: String?
    var notes: String?
    var location: String?
    var isAllDay: Bool?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startDate = "start_date"
        case endDate = "end_date"
        case calendarId = "calendar_id"
        case notes, location
        case isAllDay = "is_all_day"
        case url
    }
}

struct SearchRemindersInput: Codable {
    var completed: Bool?
    var keyword: String?
    var calendarIds: [String]?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case completed, keyword
        case calendarIds = "calendar_ids"
        case limit
    }
}

struct CreateReminderInput: Codable {
    var title: String
    var calendarId: String?
    var dueDate: String?
    var notes: String?
    var priority: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case calendarId = "calendar_id"
        case dueDate = "due_date"
        case notes, priority
    }
}

// MARK: - Date Helpers

enum CalendarDateHelper {
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    private static let localDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    private nonisolated(unsafe) static let isoLocalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    /// ISO8601 文字列をパース（タイムゾーンなしの場合はデバイスのローカルタイムとして解釈）
    static func parseDate(_ string: String) -> Date? {
        // まず標準 ISO8601 (Z or +09:00) を試行
        if let date = isoFormatter.date(from: string) {
            return date
        }
        // タイムゾーンなし → ローカルタイムとして解釈
        return localDateTimeFormatter.date(from: string)
    }

    /// Date をデバイスのローカルタイムゾーン付き ISO8601 文字列に変換
    static func formatDate(_ date: Date) -> String {
        isoLocalFormatter.string(from: date)
    }
}

// MARK: - Output Types

struct CalendarInfo: Codable, Sendable {
    var id: String
    var title: String
    var type: String
    var source: String
    var sourceType: String
    var category: String
    var color: String
    var isWritable: Bool
    var isSubscribed: Bool
    var isImmutable: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, type, source
        case sourceType = "source_type"
        case category, color
        case isWritable = "is_writable"
        case isSubscribed = "is_subscribed"
        case isImmutable = "is_immutable"
    }

    init(from calendar: EKCalendar, type: String) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.type = type
        self.source = calendar.source.title
        self.sourceType = Self.resolveSourceType(calendar.source.sourceType)
        self.category = Self.categorize(calendar)
        self.color = Self.hexColor(from: calendar.cgColor)
        self.isWritable = calendar.allowsContentModifications
        self.isSubscribed = calendar.isSubscribed
        self.isImmutable = calendar.isImmutable
    }

    private static func resolveSourceType(_ sourceType: EKSourceType) -> String {
        switch sourceType {
        case .local: return "local"
        case .exchange: return "exchange"
        case .calDAV: return "calDAV"
        case .mobileMe: return "mobileMe"
        case .subscribed: return "subscribed"
        case .birthdays: return "birthdays"
        @unknown default: return "unknown"
        }
    }

    private static func categorize(_ calendar: EKCalendar) -> String {
        if calendar.isSubscribed {
            return "subscribed"
        }
        if calendar.source.sourceType == .birthdays {
            return "birthday"
        }
        if calendar.allowsContentModifications {
            return "personal"
        }
        return "shared"
    }

    private static func hexColor(from cgColor: CGColor) -> String {
        guard let components = cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct ListCalendarsResult: Codable, Sendable {
    var calendars: [CalendarInfo]
    var hint: String
}

struct EventInfo: Codable, Sendable {
    var id: String
    var title: String
    var startDate: String
    var endDate: String
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var url: String?
    var calendarTitle: String
    var calendarId: String
    var calendarCategory: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case startDate = "start_date"
        case endDate = "end_date"
        case isAllDay = "is_all_day"
        case location, notes, url
        case calendarTitle = "calendar_title"
        case calendarId = "calendar_id"
        case calendarCategory = "calendar_category"
    }

    init(from event: EKEvent) {
        self.id = event.eventIdentifier
        self.title = event.title ?? ""
        self.startDate = CalendarDateHelper.formatDate(event.startDate)
        self.endDate = CalendarDateHelper.formatDate(event.endDate)
        self.isAllDay = event.isAllDay
        self.location = event.location
        self.notes = event.notes
        self.url = event.url?.absoluteString
        self.calendarTitle = event.calendar.title
        self.calendarId = event.calendar.calendarIdentifier
        self.calendarCategory = CalendarInfo.init(from: event.calendar, type: "event").category
    }
}

struct ReminderInfo: Codable, Sendable {
    var id: String
    var title: String
    var isCompleted: Bool
    var dueDate: String?
    var completionDate: String?
    var notes: String?
    var priority: Int
    var calendarTitle: String
    var calendarId: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case isCompleted = "is_completed"
        case dueDate = "due_date"
        case completionDate = "completion_date"
        case notes, priority
        case calendarTitle = "calendar_title"
        case calendarId = "calendar_id"
    }

    init(from reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.isCompleted = reminder.isCompleted
        self.dueDate = reminder.dueDateComponents.flatMap {
            Calendar.current.date(from: $0).map { CalendarDateHelper.formatDate($0) }
        }
        self.completionDate = reminder.completionDate.map { CalendarDateHelper.formatDate($0) }
        self.notes = reminder.notes
        self.priority = reminder.priority
        self.calendarTitle = reminder.calendar.title
        self.calendarId = reminder.calendar.calendarIdentifier
    }
}
