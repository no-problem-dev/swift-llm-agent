import Foundation

// MARK: - Input Types

struct ScheduleNotificationInput: Codable {
    var title: String
    var body: String?
    var date: String?
    var delaySeconds: Double?
    var identifier: String?

    enum CodingKeys: String, CodingKey {
        case title, body, date
        case delaySeconds = "delay_seconds"
        case identifier
    }
}

struct CancelNotificationInput: Codable {
    var identifier: String
}

// MARK: - Output Types

struct NotificationInfo: Codable, Sendable {
    var identifier: String
    var title: String
    var body: String?
    var triggerDate: String?
    var triggerDelay: Double?

    enum CodingKeys: String, CodingKey {
        case identifier, title, body
        case triggerDate = "trigger_date"
        case triggerDelay = "trigger_delay"
    }
}
