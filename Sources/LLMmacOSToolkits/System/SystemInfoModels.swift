import Foundation

// MARK: - Output Models

struct SystemInfoOutput: Codable, Sendable {
    var hostname: String
    var osVersion: String
    var processorCount: Int
    var activeProcessorCount: Int
    var physicalMemoryGB: Double
    var systemUptime: String
    var diskTotalGB: Double?
    var diskFreeGB: Double?

    enum CodingKeys: String, CodingKey {
        case hostname
        case osVersion = "os_version"
        case processorCount = "processor_count"
        case activeProcessorCount = "active_processor_count"
        case physicalMemoryGB = "physical_memory_gb"
        case systemUptime = "system_uptime"
        case diskTotalGB = "disk_total_gb"
        case diskFreeGB = "disk_free_gb"
    }
}
