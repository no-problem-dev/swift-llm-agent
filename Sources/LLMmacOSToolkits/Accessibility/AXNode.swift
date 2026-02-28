#if os(macOS)

import ApplicationServices
import Foundation

// MARK: - AXNode

/// アクセシビリティツリーの 1 ノードを表す Codable 構造体
struct AXNode: Codable, Sendable {
    var role: String?
    var title: String?
    var value: String?
    var description: String?
    var identifier: String?
    var children: [AXNode]?

    enum CodingKeys: String, CodingKey {
        case role, title, value, description, identifier, children
    }
}

// MARK: - AXNode Builder

/// AXUIElement から AXNode ツリーを再帰的に構築
enum AXNodeBuilder {

    /// AXUIElement からツリーを構築
    ///
    /// - Parameters:
    ///   - element: 起点の AXUIElement
    ///   - depth: 現在の深さ
    ///   - maxDepth: 最大深さ
    /// - Returns: 構築された AXNode
    static func buildTree(
        from element: AXUIElement,
        depth: Int = 0,
        maxDepth: Int = 5
    ) -> AXNode {
        let role: String? = AXUIElementHelpers.getAttribute(element, kAXRoleAttribute)
        let title: String? = AXUIElementHelpers.getAttribute(element, kAXTitleAttribute)
        let description: String? = AXUIElementHelpers.getAttribute(element, kAXDescriptionAttribute)
        let identifier: String? = AXUIElementHelpers.getAttribute(element, kAXIdentifierAttribute)

        // value は型が多様なため文字列化
        let value: String? = extractValue(from: element)

        var children: [AXNode]?
        if depth < maxDepth {
            if let childElements = childElements(of: element) {
                children = childElements.map { child in
                    buildTree(from: child, depth: depth + 1, maxDepth: maxDepth)
                }
                // 空の場合は nil にして JSON を簡潔に
                if children?.isEmpty == true {
                    children = nil
                }
            }
        }

        return AXNode(
            role: role,
            title: title,
            value: value,
            description: description,
            identifier: identifier,
            children: children
        )
    }

    /// 要素の子要素を取得
    private static func childElements(of element: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let children = value as? [AXUIElement] else {
            return nil
        }
        return children
    }

    /// value 属性を文字列として抽出
    private static func extractValue(from element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let val = value else { return nil }

        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        if let bool = val as? Bool { return bool ? "true" : "false" }

        return "\(val)"
    }
}

#endif
