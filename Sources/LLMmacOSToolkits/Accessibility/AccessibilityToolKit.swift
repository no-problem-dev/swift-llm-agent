#if os(macOS)

import ApplicationServices
import AppKit
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - AccessibilityToolKit

/// UI 要素の読み取り・検索・アクション実行ツールを提供する ToolKit
///
/// `AXUIElement` API を使用して、任意のアプリケーションの UI 要素ツリーを構造的に
/// 読み取り、ボタンのクリックやテキストフィールドへの入力などを自動化します。
/// Accessibility 権限が必要です。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     AccessibilityToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `ui_read_tree`: アプリの UI ツリーを JSON で取得
/// - `ui_find_element`: 条件に一致する UI 要素を検索
/// - `ui_perform_action`: UI 要素にアクションを実行
public final class AccessibilityToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "accessibility"

    /// メッセージングタイムアウト（秒）: アプリ未応答時のハング防止
    private let messagingTimeout: Float

    // MARK: - Initialization

    /// AccessibilityToolKit を作成
    ///
    /// - Parameter messagingTimeout: AX メッセージングタイムアウト秒（デフォルト: 2.0）
    public init(messagingTimeout: Float = 2.0) {
        self.messagingTimeout = messagingTimeout
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            uiReadTreeTool,
            uiFindElementTool,
            uiPerformActionTool,
        ]
    }

    // MARK: - ui_read_tree

    private var uiReadTreeTool: BuiltInTool {
        BuiltInTool(
            name: "ui_read_tree",
            description: """
                Read the accessibility tree of an application's UI. \
                Returns a structured JSON tree of UI elements (buttons, text fields, menus). \
                Requires Accessibility permission in System Settings. \
                IMPORTANT: Large trees may be truncated. Use max_depth to control depth.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "max_depth": .integer(
                        description: "Maximum tree depth (default: 5, max: 10)",
                        minimum: 1,
                        maximum: 10
                    ),
                    "window_title": .string(
                        description: "Restrict to a specific window (partial match)"
                    ),
                ],
                required: ["app_name"]
            ),
            annotations: ToolAnnotations(
                title: "Read UI Tree",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(UIReadTreeInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, app) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

            let maxDepth = min(input.maxDepth ?? 5, 10)
            let rootElement: AXUIElement

            if let windowTitle = input.windowTitle {
                guard let window = AXUIElementHelpers.findWindow(app: appElement, title: windowTitle) else {
                    return .error("Window not found (title: \(windowTitle)) in \(input.appName)")
                }
                rootElement = window
            } else {
                rootElement = appElement
            }

            let tree = AXNodeBuilder.buildTree(from: rootElement, depth: 0, maxDepth: maxDepth)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(tree)
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"

            let appName = app.localizedName ?? input.appName
            let header = "UI tree for \(appName) (max_depth: \(maxDepth)):\n"
            return .text(header + json)
        }
    }

    // MARK: - ui_find_element

    private var uiFindElementTool: BuiltInTool {
        BuiltInTool(
            name: "ui_find_element",
            description: """
                Find UI elements matching criteria within an app. \
                Returns matching elements with their roles, titles, values, and paths. \
                Use this to locate a specific button, text field, or menu item before \
                performing an action with ui_perform_action.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "role": .string(
                        description: "AX role (e.g., \"AXButton\", \"AXTextField\", \"AXMenuItem\")"
                    ),
                    "title": .string(
                        description: "Title to match (partial, case-insensitive)"
                    ),
                    "value": .string(
                        description: "Value to match (partial, case-insensitive)"
                    ),
                    "identifier": .string(
                        description: "Accessibility identifier (exact match)"
                    ),
                    "max_results": .integer(
                        description: "Maximum number of results (default: 10)",
                        minimum: 1,
                        maximum: 50
                    ),
                ],
                required: ["app_name"]
            ),
            annotations: ToolAnnotations(
                title: "Find UI Element",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(UIFindElementInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, app) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

            let maxResults = min(input.maxResults ?? 10, 50)
            var results: [FoundElement] = []
            searchElements(
                element: appElement,
                path: app.localizedName ?? input.appName,
                criteria: input,
                results: &results,
                maxResults: maxResults
            )

            if results.isEmpty {
                return .text("No UI elements found matching the specified criteria.")
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(results)
            let json = String(data: jsonData, encoding: .utf8) ?? "[]"
            return .text("Found \(results.count) element(s):\n\(json)")
        }
    }

    // MARK: - ui_perform_action

    private var uiPerformActionTool: BuiltInTool {
        BuiltInTool(
            name: "ui_perform_action",
            description: """
                Perform an action on a UI element. \
                IMPORTANT: Use ui_find_element first to identify the target. \
                Requires Accessibility permission.
                """,
            inputSchema: .object(
                properties: [
                    "app_name": .string(
                        description: "Application name (required)"
                    ),
                    "role": .string(
                        description: "Target element's AX role"
                    ),
                    "title": .string(
                        description: "Target element's title (partial match)"
                    ),
                    "identifier": .string(
                        description: "Target element's accessibility identifier"
                    ),
                    "action": .string(
                        description: "Action to perform: press, set_value, focus, confirm, cancel, show_menu, increment, decrement"
                    ),
                    "value": .string(
                        description: "Value to set (only used with set_value action)"
                    ),
                ],
                required: ["app_name", "action"]
            ),
            annotations: ToolAnnotations(
                title: "Perform UI Action",
                readOnlyHint: false,
                destructiveHint: true,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(UIPerformActionInput.self, from: data)

            guard AccessibilityPermission.isTrusted else {
                return .error(AccessibilityPermission.permissionGuide)
            }

            guard let (appElement, _) = AXUIElementHelpers.applicationElement(for: input.appName) else {
                return .error("Application not found: \(input.appName)")
            }

            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

            // 要素を検索
            let criteria = UIFindElementInput(
                appName: input.appName,
                role: input.role,
                title: input.title,
                value: nil,
                identifier: input.identifier,
                maxResults: 1
            )

            var found: [FoundElement] = []
            searchElements(
                element: appElement,
                path: input.appName,
                criteria: criteria,
                results: &found,
                maxResults: 1
            )

            guard let target = found.first else {
                var desc = [String]()
                if let role = input.role { desc.append("role=\(role)") }
                if let title = input.title { desc.append("title=\(title)") }
                if let id = input.identifier { desc.append("identifier=\(id)") }
                return .error("UI element not found matching: \(desc.joined(separator: ", "))")
            }

            // 要素を再取得して AXUIElement を得る
            guard let element = findAXElement(
                root: appElement,
                role: input.role,
                title: input.title,
                identifier: input.identifier
            ) else {
                return .error("UI element could not be located for action.")
            }

            // アクションを実行
            let result = performAction(input.action, on: element, value: input.value)
            switch result {
            case .success(let message):
                return .text("Action '\(input.action)' performed on \(target.role ?? "element") \"\(target.title ?? "untitled")\". \(message)")
            case .failure(let error):
                return .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Element Search

    private func searchElements(
        element: AXUIElement,
        path: String,
        criteria: UIFindElementInput,
        results: inout [FoundElement],
        maxResults: Int,
        depth: Int = 0
    ) {
        guard results.count < maxResults, depth < 15 else { return }

        let role: String? = AXUIElementHelpers.getAttribute(element, kAXRoleAttribute)
        let title: String? = AXUIElementHelpers.getAttribute(element, kAXTitleAttribute)
        let value: String? = {
            var val: AnyObject?
            let r = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val)
            guard r == .success else { return nil }
            if let s = val as? String { return s }
            if let n = val as? NSNumber { return n.stringValue }
            return nil
        }()
        let identifier: String? = AXUIElementHelpers.getAttribute(element, kAXIdentifierAttribute)
        let description: String? = AXUIElementHelpers.getAttribute(element, kAXDescriptionAttribute)

        var matches = true

        if let criteriaRole = criteria.role {
            matches = matches && (role?.localizedCaseInsensitiveContains(criteriaRole) ?? false)
        }
        if let criteriaTitle = criteria.title {
            matches = matches && (title?.localizedCaseInsensitiveContains(criteriaTitle) ?? false)
        }
        if let criteriaValue = criteria.value {
            matches = matches && (value?.localizedCaseInsensitiveContains(criteriaValue) ?? false)
        }
        if let criteriaId = criteria.identifier {
            matches = matches && (identifier == criteriaId)
        }

        // 少なくとも 1 つの検索条件が指定されている場合のみマッチ
        let hasCriteria = criteria.role != nil || criteria.title != nil
            || criteria.value != nil || criteria.identifier != nil

        if matches && hasCriteria {
            results.append(FoundElement(
                role: role,
                title: title,
                value: value,
                description: description,
                identifier: identifier,
                path: path
            ))
        }

        // 子要素を再帰的に探索
        var childrenRef: AnyObject?
        let childResult = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        )
        guard childResult == .success, let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            guard results.count < maxResults else { return }
            let childRole: String? = AXUIElementHelpers.getAttribute(child, kAXRoleAttribute)
            let childTitle: String? = AXUIElementHelpers.getAttribute(child, kAXTitleAttribute)
            let childPath: String
            if let childTitle, !childTitle.isEmpty {
                childPath = "\(path) > \(childRole ?? "?")[\"\(childTitle)\"]"
            } else {
                childPath = "\(path) > \(childRole ?? "?")"
            }
            searchElements(
                element: child,
                path: childPath,
                criteria: criteria,
                results: &results,
                maxResults: maxResults,
                depth: depth + 1
            )
        }
    }

    // MARK: - Find AXUIElement

    private func findAXElement(
        root: AXUIElement,
        role: String?,
        title: String?,
        identifier: String?,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 15 else { return nil }

        let elemRole: String? = AXUIElementHelpers.getAttribute(root, kAXRoleAttribute)
        let elemTitle: String? = AXUIElementHelpers.getAttribute(root, kAXTitleAttribute)
        let elemId: String? = AXUIElementHelpers.getAttribute(root, kAXIdentifierAttribute)

        var matches = true
        var hasCriteria = false

        if let role {
            hasCriteria = true
            matches = matches && (elemRole?.localizedCaseInsensitiveContains(role) ?? false)
        }
        if let title {
            hasCriteria = true
            matches = matches && (elemTitle?.localizedCaseInsensitiveContains(title) ?? false)
        }
        if let identifier {
            hasCriteria = true
            matches = matches && (elemId == identifier)
        }

        if matches && hasCriteria { return root }

        var childrenRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            root, kAXChildrenAttribute as CFString, &childrenRef
        )
        guard result == .success, let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findAXElement(
                root: child, role: role, title: title, identifier: identifier, depth: depth + 1
            ) {
                return found
            }
        }

        return nil
    }

    // MARK: - Action Execution

    private func performAction(
        _ action: String,
        on element: AXUIElement,
        value: String?
    ) -> Result<String, AccessibilityToolKitError> {
        switch action {
        case "press":
            let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Pressed.")

        case "set_value":
            guard let value else {
                return .failure(.actionFailed(action: action, message: "value parameter is required for set_value"))
            }
            let err = AXUIElementSetAttributeValue(
                element, kAXValueAttribute as CFString, value as CFTypeRef
            )
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Value set to \"\(value)\".")

        case "focus":
            let err = AXUIElementSetAttributeValue(
                element, kAXFocusedAttribute as CFString, true as CFTypeRef
            )
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Focused.")

        case "confirm":
            let err = AXUIElementPerformAction(element, kAXConfirmAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Confirmed.")

        case "cancel":
            let err = AXUIElementPerformAction(element, kAXCancelAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Cancelled.")

        case "show_menu":
            let err = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Menu shown.")

        case "increment":
            let err = AXUIElementPerformAction(element, kAXIncrementAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Incremented.")

        case "decrement":
            let err = AXUIElementPerformAction(element, kAXDecrementAction as CFString)
            if err != .success {
                return .failure(.actionFailed(action: action, message: "AXError \(err.rawValue)"))
            }
            return .success("Decremented.")

        default:
            return .failure(.actionFailed(
                action: action,
                message: "Unknown action. Valid actions: press, set_value, focus, confirm, cancel, show_menu, increment, decrement"
            ))
        }
    }
}

// MARK: - Input Types

private struct UIReadTreeInput: Codable {
    var appName: String
    var maxDepth: Int?
    var windowTitle: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case maxDepth = "max_depth"
        case windowTitle = "window_title"
    }
}

struct UIFindElementInput: Codable {
    var appName: String
    var role: String?
    var title: String?
    var value: String?
    var identifier: String?
    var maxResults: Int?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case role, title, value, identifier
        case maxResults = "max_results"
    }
}

private struct UIPerformActionInput: Codable {
    var appName: String
    var role: String?
    var title: String?
    var identifier: String?
    var action: String
    var value: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case role, title, identifier, action, value
    }
}

// MARK: - Output Types

private struct FoundElement: Codable {
    var role: String?
    var title: String?
    var value: String?
    var description: String?
    var identifier: String?
    var path: String
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（AXUIElement は macOS のみ）
public final class AccessibilityToolKit: ToolKit, Sendable {
    public let name: String = "accessibility"
    public init(messagingTimeout: Float = 2.0) {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "ui_read_tree",
                description: "Read the accessibility tree of an app. (macOS only)",
                inputSchema: .object(
                    properties: ["app_name": .string(description: "Application name")],
                    required: ["app_name"]
                ),
                annotations: .readOnly
            ) { _ in
                .error("AccessibilityToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "ui_find_element",
                description: "Find UI elements matching criteria. (macOS only)",
                inputSchema: .object(
                    properties: ["app_name": .string(description: "Application name")],
                    required: ["app_name"]
                ),
                annotations: .readOnly
            ) { _ in
                .error("AccessibilityToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "ui_perform_action",
                description: "Perform an action on a UI element. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "app_name": .string(description: "Application name"),
                        "action": .string(description: "Action to perform"),
                    ],
                    required: ["app_name", "action"]
                ),
                annotations: .destructive
            ) { _ in
                .error("AccessibilityToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
