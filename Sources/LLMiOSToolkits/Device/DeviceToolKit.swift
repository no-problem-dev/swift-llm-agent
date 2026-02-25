#if canImport(UIKit)
import Foundation
import LLMClient
import LLMTool
import LLMMCP
import UIKit

// MARK: - DeviceToolKit

/// デバイス情報と基本操作を提供する ToolKit
///
/// UIDevice, ProcessInfo, UIScreen を使用して、
/// デバイス情報の取得と画面輝度の操作を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     DeviceToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_device_info`: デバイス名・モデル・OS・バッテリー情報を取得
/// - `get_screen_brightness`: 画面の明るさを取得
/// - `set_screen_brightness`: 画面の明るさを設定
/// - `open_settings`: 設定アプリの特定画面を開く
public final class DeviceToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "device"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            getDeviceInfoTool,
            getScreenBrightnessTool,
            setScreenBrightnessTool,
            openSettingsTool,
        ]
    }

    // MARK: - get_device_info

    private var getDeviceInfoTool: BuiltInTool {
        BuiltInTool(
            name: "get_device_info",
            description: "Get device information including name, model, OS version, and battery status.",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Device Info",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let device = await MainActor.run { UIDevice.current }
            let processInfo = ProcessInfo.processInfo

            await MainActor.run { device.isBatteryMonitoringEnabled = true }

            let batteryLevel = await MainActor.run { device.batteryLevel }
            let batteryState = await MainActor.run { device.batteryState }

            struct DeviceInfo: Codable {
                var name: String
                var model: String
                var systemName: String
                var systemVersion: String
                var batteryLevel: Int?
                var batteryState: String
                var processorCount: Int
                var physicalMemory: String
                var isLowPowerMode: Bool

                enum CodingKeys: String, CodingKey {
                    case name, model
                    case systemName = "system_name"
                    case systemVersion = "system_version"
                    case batteryLevel = "battery_level"
                    case batteryState = "battery_state"
                    case processorCount = "processor_count"
                    case physicalMemory = "physical_memory"
                    case isLowPowerMode = "is_low_power_mode"
                }
            }

            let stateString: String
            switch batteryState {
            case .unplugged: stateString = "unplugged"
            case .charging: stateString = "charging"
            case .full: stateString = "full"
            case .unknown: stateString = "unknown"
            @unknown default: stateString = "unknown"
            }

            let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824
            let info = DeviceInfo(
                name: await MainActor.run { device.name },
                model: await MainActor.run { device.model },
                systemName: await MainActor.run { device.systemName },
                systemVersion: await MainActor.run { device.systemVersion },
                batteryLevel: batteryLevel >= 0 ? Int(batteryLevel * 100) : nil,
                batteryState: stateString,
                processorCount: processInfo.processorCount,
                physicalMemory: String(format: "%.1f GB", memoryGB),
                isLowPowerMode: processInfo.isLowPowerModeEnabled
            )

            return try .encoded(info)
        }
    }

    // MARK: - get_screen_brightness

    private var getScreenBrightnessTool: BuiltInTool {
        BuiltInTool(
            name: "get_screen_brightness",
            description: "Get the current screen brightness level (0-100).",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Screen Brightness",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let brightness = await MainActor.run {
                Int(UIScreen.main.brightness * 100)
            }
            struct BrightnessInfo: Codable { var brightness: Int }
            return try .encoded(BrightnessInfo(brightness: brightness))
        }
    }

    // MARK: - set_screen_brightness

    private var setScreenBrightnessTool: BuiltInTool {
        BuiltInTool(
            name: "set_screen_brightness",
            description: "Set the screen brightness level (0-100).",
            inputSchema: .object(
                properties: [
                    "brightness": .integer(
                        description: "Brightness level from 0 (darkest) to 100 (brightest)"
                    ),
                ],
                required: ["brightness"]
            ),
            annotations: ToolAnnotations(
                title: "Set Screen Brightness",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable { var brightness: Int }
            let input = try JSONDecoder().decode(Input.self, from: data)
            let clamped = max(0, min(100, input.brightness))

            await MainActor.run {
                UIScreen.main.brightness = CGFloat(clamped) / 100.0
            }

            return .text("Screen brightness set to \(clamped)%.")
        }
    }

    // MARK: - open_settings

    private var openSettingsTool: BuiltInTool {
        BuiltInTool(
            name: "open_settings",
            description: "Open the Settings app. Optionally open a specific settings page.",
            inputSchema: .object(
                properties: [
                    "page": .string(
                        description: "Settings page to open: 'general', 'wifi', 'bluetooth', 'notifications', 'privacy', 'display', 'sounds', 'battery'. "
                            + "Omit to open the main Settings page."
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Open Settings",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { data in
            struct Input: Codable { var page: String? }
            let input = try JSONDecoder().decode(Input.self, from: data)

            let urlString: String
            if let page = input.page?.lowercased() {
                switch page {
                case "general":
                    urlString = "App-Prefs:root=General"
                case "wifi":
                    urlString = "App-Prefs:root=WIFI"
                case "bluetooth":
                    urlString = "App-Prefs:root=Bluetooth"
                case "notifications":
                    urlString = "App-Prefs:root=NOTIFICATIONS_ID"
                case "privacy":
                    urlString = "App-Prefs:root=Privacy"
                case "display":
                    urlString = "App-Prefs:root=DISPLAY"
                case "sounds":
                    urlString = "App-Prefs:root=Sounds"
                case "battery":
                    urlString = "App-Prefs:root=BATTERY_USAGE"
                default:
                    urlString = UIApplication.openSettingsURLString
                }
            } else {
                urlString = UIApplication.openSettingsURLString
            }

            guard let url = URL(string: urlString) else {
                return .error("Failed to create settings URL.")
            }

            let opened = await MainActor.run {
                UIApplication.shared.canOpenURL(url)
            }

            if opened {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
                return .text("Settings opened.")
            } else {
                // フォールバック: アプリ設定を開く
                if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
                    await MainActor.run {
                        UIApplication.shared.open(appSettingsURL)
                    }
                    return .text("App settings opened.")
                }
                return .error("Failed to open settings.")
            }
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// macOS 用のスタブ
public final class DeviceToolKit: ToolKit, Sendable {
    public let name: String = "device"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "get_device_info",
                description: "Get device information. (iOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                let processInfo = ProcessInfo.processInfo
                struct MacDeviceInfo: Codable {
                    var hostName: String
                    var systemVersion: String
                    var processorCount: Int
                    var physicalMemory: String

                    enum CodingKeys: String, CodingKey {
                        case hostName = "host_name"
                        case systemVersion = "system_version"
                        case processorCount = "processor_count"
                        case physicalMemory = "physical_memory"
                    }
                }
                let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824
                let info = MacDeviceInfo(
                    hostName: processInfo.hostName,
                    systemVersion: processInfo.operatingSystemVersionString,
                    processorCount: processInfo.processorCount,
                    physicalMemory: String(format: "%.1f GB", memoryGB)
                )
                return try .encoded(info)
            },
            BuiltInTool(
                name: "get_screen_brightness",
                description: "Get screen brightness. (iOS only — not available on macOS)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in .error("Screen brightness control is only available on iOS.") },
            BuiltInTool(
                name: "set_screen_brightness",
                description: "Set screen brightness. (iOS only — not available on macOS)",
                inputSchema: .object(
                    properties: ["brightness": .integer(description: "Brightness 0-100")],
                    required: ["brightness"]
                ),
                annotations: .idempotentWrite
            ) { _ in .error("Screen brightness control is only available on iOS.") },
            BuiltInTool(
                name: "open_settings",
                description: "Open settings. (iOS only — not available on macOS)",
                inputSchema: .object(
                    properties: ["page": .string(description: "Settings page")],
                    required: []
                ),
                annotations: .readOnly
            ) { _ in .error("Open settings is only available on iOS.") },
        ]
    }
}
#endif
