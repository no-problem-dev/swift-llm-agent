#if os(macOS)

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - WindowManagementToolKit

/// ウィンドウの一覧・移動・リサイズ・フォーカス管理ツールを提供する ToolKit
///
/// `CGWindowListCopyWindowInfo`（権限不要）で読み取り、
/// `AXUIElement`（Accessibility 権限要）で操作を行います。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     WindowManagementToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `window_list`: 画面上のウィンドウ一覧を取得
/// - `window_focus`: ウィンドウを最前面に表示
/// - `window_resize`: ウィンドウの位置・サイズを変更
/// - `window_minimize`: ウィンドウを最小化 / 復元
public final class WindowManagementToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "window-management"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            windowListTool,
            windowFocusTool,
            windowResizeTool,
            windowMinimizeTool,
        ]
    }

    // MARK: - window_list

    private var windowListTool: BuiltInTool {
        BuiltInTool(
            name: "window_list",
            description: """
                List all visible windows across all applications. \
                Returns window title, owning app name, position, size, and whether focused. \
                Does not require Accessibility permission for basic info.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Filter windows by application name (optional)"
                    ),
                ],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Windows",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(WindowListInput.self, from: data)

            guard let windowInfoList = CGWindowListCopyWindowInfo(
                [.excludeDesktopElements, .optionOnScreenOnly],
                kCGNullWindowID
            ) as? [[String: Any]] else {
                return .error("Failed to retrieve window list.")
            }

            // 現在アクティブなアプリの PID を取得
            let activeApp = NSWorkspace.shared.frontmostApplication
            let activePID = activeApp?.processIdentifier

            var windows: [WindowInfo] = []
            for info in windowInfoList {
                // 通常ウィンドウ（layer == 0）のみ
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                    continue
                }

                let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"

                // app_name フィルタ
                if let filterName = input.appName {
                    guard ownerName.localizedCaseInsensitiveContains(filterName) else {
                        continue
                    }
                }

                let title = info[kCGWindowName as String] as? String
                let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let ownerPID = info[kCGWindowOwnerPID as String] as? Int32

                let windowInfo = WindowInfo(
                    ownerName: ownerName,
                    title: title,
                    x: bounds["X"] as? Int ?? 0,
                    y: bounds["Y"] as? Int ?? 0,
                    width: bounds["Width"] as? Int ?? 0,
                    height: bounds["Height"] as? Int ?? 0,
                    isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? true,
                    isFocused: ownerPID == activePID
                )
                windows.append(windowInfo)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(windows)
            let json = String(data: jsonData, encoding: .utf8) ?? "[]"
            return .text(json)
        }
    }

    // MARK: - window_focus

    private var windowFocusTool: BuiltInTool {
        BuiltInTool(
            name: "window_focus",
            description: """
                Bring a window to the front. Requires Accessibility permission. \
                Specify the application name and optionally a window title (partial match).
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "window_title": .string(
                        description: "Window title for partial match (optional, defaults to first window)"
                    ),
                ],
                required: ["app_name"]
            ),
            annotations: ToolAnnotations(
                title: "Focus Window",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(WindowFocusInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, app) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            guard let window = AXUIElementHelpers.findWindow(app: appElement, title: input.windowTitle) else {
                let target = input.windowTitle ?? "any"
                return .error("Window not found (title: \(target)) in \(input.appName)")
            }

            let raiseResult = AXUIElementHelpers.focusWindow(window)
            guard raiseResult == .success else {
                return .error("Failed to raise window (AXError: \(raiseResult.rawValue))")
            }

            app.activate()

            let windowTitle: String? = AXUIElementHelpers.getAttribute(window, kAXTitleAttribute)
            let appName = app.localizedName ?? input.appName
            return .text("Focused window \"\(windowTitle ?? "untitled")\" of \(appName).")
        }
    }

    // MARK: - window_resize

    private var windowResizeTool: BuiltInTool {
        BuiltInTool(
            name: "window_resize",
            description: """
                Move and/or resize a window. Requires Accessibility permission. \
                Specify position (x, y) and/or size (width, height). \
                Only provided values are changed; omitted values remain unchanged.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "window_title": .string(
                        description: "Window title for partial match (optional)"
                    ),
                    "x": .number(description: "New X position"),
                    "y": .number(description: "New Y position"),
                    "width": .number(description: "New width"),
                    "height": .number(description: "New height"),
                ],
                required: ["app_name"]
            ),
            annotations: ToolAnnotations(
                title: "Resize Window",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(WindowResizeInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, app) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            guard let window = AXUIElementHelpers.findWindow(app: appElement, title: input.windowTitle) else {
                let target = input.windowTitle ?? "any"
                return .error("Window not found (title: \(target)) in \(input.appName)")
            }

            var changes: [String] = []

            // 位置の変更
            if input.x != nil || input.y != nil {
                let currentPos = AXUIElementHelpers.windowPosition(window) ?? .zero
                let newX = input.x.map { CGFloat($0) } ?? currentPos.x
                let newY = input.y.map { CGFloat($0) } ?? currentPos.y
                let result = AXUIElementHelpers.moveWindow(window, to: CGPoint(x: newX, y: newY))
                if result != .success {
                    return .error("Failed to move window (AXError: \(result.rawValue))")
                }
                changes.append("moved to (\(Int(newX)), \(Int(newY)))")
            }

            // サイズの変更
            if input.width != nil || input.height != nil {
                let currentSize = AXUIElementHelpers.windowSize(window) ?? .zero
                let newW = input.width.map { CGFloat($0) } ?? currentSize.width
                let newH = input.height.map { CGFloat($0) } ?? currentSize.height
                let result = AXUIElementHelpers.resizeWindow(window, to: CGSize(width: newW, height: newH))
                if result != .success {
                    return .error("Failed to resize window (AXError: \(result.rawValue))")
                }
                changes.append("resized to \(Int(newW))x\(Int(newH))")
            }

            if changes.isEmpty {
                return .text("No changes specified. Provide x/y for position or width/height for size.")
            }

            let appName = app.localizedName ?? input.appName
            return .text("Window of \(appName): \(changes.joined(separator: ", ")).")
        }
    }

    // MARK: - window_minimize

    private var windowMinimizeTool: BuiltInTool {
        BuiltInTool(
            name: "window_minimize",
            description: """
                Minimize or restore a window. Requires Accessibility permission. \
                By default minimizes the window. Set restore=true to un-minimize.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "window_title": .string(
                        description: "Window title for partial match (optional)"
                    ),
                    "restore": .boolean(
                        description: "Set to true to restore (un-minimize) the window (default: false)"
                    ),
                ],
                required: ["app_name"]
            ),
            annotations: ToolAnnotations(
                title: "Minimize Window",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(WindowMinimizeInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, app) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            let shouldRestore = input.restore ?? false

            // restore の場合は最小化されたウィンドウも含める
            let window: AXUIElement?
            if shouldRestore {
                // 最小化されたウィンドウを探す
                let allWindows = AXUIElementHelpers.windows(for: appElement)
                window = allWindows.first { w in
                    let isMinimized: Bool = AXUIElementHelpers.getAttribute(w, kAXMinimizedAttribute) ?? false
                    if !isMinimized { return false }
                    guard let title = input.windowTitle else { return true }
                    let wTitle: String? = AXUIElementHelpers.getAttribute(w, kAXTitleAttribute)
                    return wTitle?.localizedCaseInsensitiveContains(title) ?? false
                }
            } else {
                window = AXUIElementHelpers.findWindow(app: appElement, title: input.windowTitle)
            }

            guard let targetWindow = window else {
                let target = input.windowTitle ?? "any"
                return .error("Window not found (title: \(target)) in \(input.appName)")
            }

            let result = AXUIElementHelpers.setMinimized(targetWindow, !shouldRestore)
            guard result == .success else {
                return .error("Failed to \(shouldRestore ? "restore" : "minimize") window (AXError: \(result.rawValue))")
            }

            let appName = app.localizedName ?? input.appName
            let action = shouldRestore ? "Restored" : "Minimized"
            return .text("\(action) window of \(appName).")
        }
    }
}

// MARK: - Internal Input Types

private struct WindowListInput: Codable {
    var appName: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（ウィンドウ管理は macOS のみ）
public final class WindowManagementToolKit: ToolKit, Sendable {
    public let name: String = "window-management"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "window_list",
                description: "List visible windows. (macOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                .error("WindowManagementToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "window_focus",
                description: "Focus a window. (macOS only)",
                inputSchema: .object(
                    properties: ["app_name": .string(description: "Application name")],
                    required: ["app_name"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false)
            ) { _ in
                .error("WindowManagementToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "window_resize",
                description: "Resize a window. (macOS only)",
                inputSchema: .object(
                    properties: ["app_name": .string(description: "Application name")],
                    required: ["app_name"]
                ),
                annotations: .idempotentWrite
            ) { _ in
                .error("WindowManagementToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "window_minimize",
                description: "Minimize or restore a window. (macOS only)",
                inputSchema: .object(
                    properties: ["app_name": .string(description: "Application name")],
                    required: ["app_name"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false)
            ) { _ in
                .error("WindowManagementToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
