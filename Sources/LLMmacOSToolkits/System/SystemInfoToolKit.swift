import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - SystemInfoToolKit

/// macOS のシステム情報を取得するツールを提供する ToolKit
///
/// `ProcessInfo` や `FileManager` を使用して、
/// ホスト名・OS バージョン・メモリ・CPU・ディスク容量などのシステム情報を返します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     SystemInfoToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_system_info`: システム情報を一括取得
public final class SystemInfoToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "system-info"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [getSystemInfoTool]
    }

    // MARK: - get_system_info

    private var getSystemInfoTool: BuiltInTool {
        BuiltInTool(
            name: "get_system_info",
            description: """
                Get macOS system information including hostname, OS version, \
                CPU count, physical memory, system uptime, and disk usage.
                """,
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get System Info",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let info = ProcessInfo.processInfo
            let osVersion = info.operatingSystemVersion

            // 稼働時間をフォーマット
            let uptime = info.systemUptime
            let hours = Int(uptime) / 3600
            let minutes = (Int(uptime) % 3600) / 60
            let uptimeString: String
            if hours > 24 {
                let days = hours / 24
                let remainingHours = hours % 24
                uptimeString = "\(days)d \(remainingHours)h \(minutes)m"
            } else {
                uptimeString = "\(hours)h \(minutes)m"
            }

            // ディスク容量
            var diskTotalGB: Double?
            var diskFreeGB: Double?
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
                if let total = attrs[.systemSize] as? Int64 {
                    diskTotalGB = Double(total) / 1_073_741_824
                }
                if let free = attrs[.systemFreeSize] as? Int64 {
                    diskFreeGB = Double(free) / 1_073_741_824
                }
            }

            let output = SystemInfoOutput(
                hostname: info.hostName,
                osVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
                processorCount: info.processorCount,
                activeProcessorCount: info.activeProcessorCount,
                physicalMemoryGB: Double(info.physicalMemory) / 1_073_741_824,
                systemUptime: uptimeString,
                diskTotalGB: diskTotalGB.map { (($0 * 10).rounded() / 10) },
                diskFreeGB: diskFreeGB.map { (($0 * 10).rounded() / 10) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }
}
