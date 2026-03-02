#if canImport(HomeKit)
@preconcurrency import HomeKit
import Foundation
import LLMClient
import LLMTool
import LLMMCP
import os

// MARK: - HomeToolKit

/// スマートホームデバイスを操作する ToolKit
///
/// HomeKit を使用して、デバイスの一覧取得、状態確認、
/// 操作（オン/オフ、明るさ等）、シーンの実行を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     HomeToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `list_devices`: ホームデバイス一覧
/// - `get_device_status`: デバイスの現在状態
/// - `control_device`: デバイス操作（オン/オフ、明るさ、温度等）
/// - `list_scenes`: シーン一覧
/// - `activate_scene`: シーン実行
public final class HomeToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "home"

    /// `HMHomeManager` の遅延初期化用ロック
    ///
    /// `HMHomeManager()` のインスタンス化は HomeKit の許可ダイアログをトリガーするため、
    /// ツールが実際に呼び出されるまで生成を遅延させる。
    private let state: OSAllocatedUnfairLock<HMHomeManager?>

    /// スレッドセーフに `HMHomeManager` を取得（初回アクセス時に生成）
    private var homeManager: HMHomeManager {
        state.withLock { manager in
            if let existing = manager { return existing }
            let new = HMHomeManager()
            manager = new
            return new
        }
    }

    // MARK: - Initialization

    public init() {
        self.state = OSAllocatedUnfairLock(initialState: nil)
    }

    /// テスト用 DI イニシャライザ
    public init(homeManager: HMHomeManager) {
        self.state = OSAllocatedUnfairLock(initialState: homeManager)
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            listDevicesTool,
            getDeviceStatusTool,
            controlDeviceTool,
            listScenesTool,
            activateSceneTool,
        ]
    }

    // MARK: - Helpers

    private var primaryHome: HMHome? {
        homeManager.primaryHome ?? homeManager.homes.first
    }

    private func findAccessory(name: String?, id: String?) -> HMAccessory? {
        guard let home = primaryHome else { return nil }
        if let id {
            return home.accessories.first { $0.uniqueIdentifier.uuidString == id }
        }
        if let name {
            let lowered = name.lowercased()
            return home.accessories.first {
                $0.name.lowercased().contains(lowered)
            }
        }
        return nil
    }

    private static func categoryName(_ category: HMAccessoryCategory) -> String {
        switch category.categoryType {
        case HMAccessoryCategoryTypeLightbulb: return "light"
        case HMAccessoryCategoryTypeSwitch, HMAccessoryCategoryTypeOutlet: return "switch"
        case HMAccessoryCategoryTypeThermostat: return "thermostat"
        case HMAccessoryCategoryTypeFan: return "fan"
        case HMAccessoryCategoryTypeDoorLock: return "lock"
        case HMAccessoryCategoryTypeDoor: return "door"
        case HMAccessoryCategoryTypeWindow: return "window"
        case HMAccessoryCategoryTypeSensor: return "sensor"
        default: return category.categoryType
        }
    }

    // MARK: - list_devices

    private var listDevicesTool: BuiltInTool {
        BuiltInTool(
            name: "list_devices",
            description: "List all smart home devices (accessories) in the primary home. "
                + "Can filter by room name.",
            inputSchema: .object(
                properties: [
                    "room": .string(description: "Filter by room name (optional)"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Devices",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [weak self] data in
            guard let self else { return .error("HomeToolKit is no longer available.") }
            let input = try JSONDecoder().decode(ListDevicesInput.self, from: data)
            let homeManager = self.homeManager

            guard let home = homeManager.primaryHome ?? homeManager.homes.first else {
                return .error("No HomeKit home found. Set up a home in the Home app first.")
            }

            var accessories = home.accessories
            if let room = input.room?.lowercased() {
                accessories = accessories.filter {
                    $0.room?.name.lowercased().contains(room) ?? false
                }
            }

            let devices = accessories.map { acc in
                HomeDeviceInfo(
                    id: acc.uniqueIdentifier.uuidString,
                    name: acc.name,
                    room: acc.room?.name,
                    category: Self.categoryName(acc.category),
                    isReachable: acc.isReachable
                )
            }

            return try .encoded(devices)
        }
    }

    // MARK: - get_device_status

    private var getDeviceStatusTool: BuiltInTool {
        BuiltInTool(
            name: "get_device_status",
            description: "Get the current status of a specific device. "
                + "Provide the device name or ID from list_devices.",
            inputSchema: .object(
                properties: [
                    "name": .string(description: "Device name (partial match)"),
                    "id": .string(description: "Device ID from list_devices"),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Device Status",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [weak self] data in
            guard let self else { return .error("HomeToolKit is no longer available.") }
            let input = try JSONDecoder().decode(GetDeviceStatusInput.self, from: data)

            guard let accessory = findAccessory(name: input.name, id: input.id) else {
                return .error(
                    "Device not found. Use list_devices to see available devices."
                )
            }

            // 全サービスの characteristics を読み取り
            var characteristics: [CharacteristicInfo] = []
            for service in accessory.services {
                for char in service.characteristics {
                    if char.properties.contains(HMCharacteristicPropertyReadable) {
                        try? await char.readValue()
                    }
                    characteristics.append(CharacteristicInfo(
                        type: char.localizedDescription,
                        value: char.value.map { "\($0)" },
                        isReadable: char.properties.contains(HMCharacteristicPropertyReadable),
                        isWritable: char.properties.contains(HMCharacteristicPropertyWritable)
                    ))
                }
            }

            let status = DeviceStatusInfo(
                id: accessory.uniqueIdentifier.uuidString,
                name: accessory.name,
                room: accessory.room?.name,
                category: Self.categoryName(accessory.category),
                isReachable: accessory.isReachable,
                characteristics: characteristics
            )

            return try .encoded(status)
        }
    }

    // MARK: - control_device

    private var controlDeviceTool: BuiltInTool {
        BuiltInTool(
            name: "control_device",
            description: "Control a smart home device. "
                + "Actions: 'on', 'off', 'toggle', 'set_brightness' (0-100), 'set_temperature' (celsius). "
                + "Provide the device name or ID.",
            inputSchema: .object(
                properties: [
                    "name": .string(description: "Device name (partial match)"),
                    "id": .string(description: "Device ID from list_devices"),
                    "action": .string(
                        description: "Action: 'on', 'off', 'toggle', 'set_brightness', 'set_temperature'"
                    ),
                    "value": .string(
                        description: "Value for the action (e.g., '80' for brightness, '24' for temperature)"
                    ),
                ],
                required: ["action"]
            ),
            annotations: ToolAnnotations(
                title: "Control Device",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [weak self] data in
            guard let self else { return .error("HomeToolKit is no longer available.") }
            let input = try JSONDecoder().decode(ControlDeviceInput.self, from: data)

            guard let accessory = findAccessory(name: input.name, id: input.id) else {
                return .error("Device not found. Use list_devices to see available devices.")
            }

            guard accessory.isReachable else {
                return .error("Device '\(accessory.name)' is not reachable.")
            }

            // Power on/off の characteristic を探す
            let powerChar = accessory.services.flatMap { $0.characteristics }
                .first { $0.characteristicType == HMCharacteristicTypePowerState }

            switch input.action.lowercased() {
            case "on":
                guard let char = powerChar else {
                    return .error("Device does not support power control.")
                }
                do {
                    try await char.writeValue(true)
                    return .text("'\(accessory.name)' turned on.")
                } catch {
                    return .error("Failed to turn on: \(error.localizedDescription)")
                }

            case "off":
                guard let char = powerChar else {
                    return .error("Device does not support power control.")
                }
                do {
                    try await char.writeValue(false)
                    return .text("'\(accessory.name)' turned off.")
                } catch {
                    return .error("Failed to turn off: \(error.localizedDescription)")
                }

            case "toggle":
                guard let char = powerChar else {
                    return .error("Device does not support power control.")
                }
                do {
                    try await char.readValue()
                    let current = char.value as? Bool ?? false
                    try await char.writeValue(!current)
                    return .text("'\(accessory.name)' toggled \(!current ? "on" : "off").")
                } catch {
                    return .error("Failed to toggle: \(error.localizedDescription)")
                }

            case "set_brightness":
                let brightnessChar = accessory.services.flatMap { $0.characteristics }
                    .first { $0.characteristicType == HMCharacteristicTypeBrightness }
                guard let char = brightnessChar else {
                    return .error("Device does not support brightness control.")
                }
                guard let valueStr = input.value, let value = Int(valueStr) else {
                    return .error("Brightness value required (0-100).")
                }
                do {
                    try await char.writeValue(max(0, min(100, value)))
                    return .text("'\(accessory.name)' brightness set to \(value)%.")
                } catch {
                    return .error("Failed to set brightness: \(error.localizedDescription)")
                }

            case "set_temperature":
                let tempChar = accessory.services.flatMap { $0.characteristics }
                    .first { $0.characteristicType == HMCharacteristicTypeTargetTemperature }
                guard let char = tempChar else {
                    return .error("Device does not support temperature control.")
                }
                guard let valueStr = input.value, let value = Double(valueStr) else {
                    return .error("Temperature value required (celsius).")
                }
                do {
                    try await char.writeValue(value)
                    return .text("'\(accessory.name)' target temperature set to \(value)°C.")
                } catch {
                    return .error("Failed to set temperature: \(error.localizedDescription)")
                }

            default:
                return .error(
                    "Unknown action: '\(input.action)'. "
                    + "Available: 'on', 'off', 'toggle', 'set_brightness', 'set_temperature'."
                )
            }
        }
    }

    // MARK: - list_scenes

    private var listScenesTool: BuiltInTool {
        BuiltInTool(
            name: "list_scenes",
            description: "List all available HomeKit scenes (action sets).",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Scenes",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [weak self] data in
            guard let self else { return .error("HomeToolKit is no longer available.") }
            let homeManager = self.homeManager

            guard let home = homeManager.primaryHome ?? homeManager.homes.first else {
                return .error("No HomeKit home found.")
            }

            let scenes = home.actionSets.map { actionSet in
                HomeSceneInfo(
                    id: actionSet.uniqueIdentifier.uuidString,
                    name: actionSet.name
                )
            }

            return try .encoded(scenes)
        }
    }

    // MARK: - activate_scene

    private var activateSceneTool: BuiltInTool {
        BuiltInTool(
            name: "activate_scene",
            description: "Activate a HomeKit scene (action set) by name. "
                + "Use list_scenes to see available scenes.",
            inputSchema: .object(
                properties: [
                    "name": .string(description: "Scene name to activate"),
                ],
                required: ["name"]
            ),
            annotations: ToolAnnotations(
                title: "Activate Scene",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { [weak self] data in
            guard let self else { return .error("HomeToolKit is no longer available.") }
            let input = try JSONDecoder().decode(ActivateSceneInput.self, from: data)
            let homeManager = self.homeManager

            guard let home = homeManager.primaryHome ?? homeManager.homes.first else {
                return .error("No HomeKit home found.")
            }

            let lowered = input.name.lowercased()
            guard let actionSet = home.actionSets.first(where: {
                $0.name.lowercased().contains(lowered)
            }) else {
                return .error(
                    "Scene '\(input.name)' not found. Use list_scenes to see available scenes."
                )
            }

            do {
                try await home.executeActionSet(actionSet)
                return .text("Scene '\(actionSet.name)' activated.")
            } catch {
                return .error("Failed to activate scene: \(error.localizedDescription)")
            }
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// HomeKit 非対応プラットフォーム用のスタブ
public final class HomeToolKit: ToolKit, Sendable {
    public let name: String = "home"
    public init() {}
    public var tools: [any Tool] { [] }
}
#endif
