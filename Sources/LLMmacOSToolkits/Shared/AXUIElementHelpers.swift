#if os(macOS)

import ApplicationServices
import AppKit
import Foundation

// MARK: - AXUIElementHelpers

/// AXUIElement の汎用ブリッジユーティリティ
enum AXUIElementHelpers {

    // MARK: - App Resolution

    /// アプリ名から NSRunningApplication を検索
    static func findRunningApp(name: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications

        // バンドルID で検索
        if let app = apps.first(where: { $0.bundleIdentifier == name }) {
            return app
        }

        // アプリ名で検索（大文字小文字を無視）
        let lowered = name.lowercased()
        if let app = apps.first(where: {
            $0.localizedName?.lowercased() == lowered
        }) {
            return app
        }

        return nil
    }

    /// アプリ名から AXUIElement（アプリケーション要素）を生成
    static func applicationElement(for appName: String) -> (AXUIElement, NSRunningApplication)? {
        guard let app = findRunningApp(name: appName) else {
            return nil
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return (element, app)
    }

    // MARK: - Generic Attribute Access

    /// AXUIElement から属性値を取得
    static func getAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    /// AXUIElement に属性値を設定
    @discardableResult
    static func setAttribute(_ element: AXUIElement, _ attribute: String, _ value: AnyObject) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    // MARK: - Window Discovery

    /// アプリのウィンドウ一覧を取得
    static func windows(for appElement: AXUIElement) -> [AXUIElement] {
        guard let windowList: CFArray = getAttribute(appElement, kAXWindowsAttribute) else {
            return []
        }
        var windows: [AXUIElement] = []
        for i in 0..<CFArrayGetCount(windowList) {
            let ptr = CFArrayGetValueAtIndex(windowList, i)
            let window = Unmanaged<AXUIElement>.fromOpaque(ptr!).takeUnretainedValue()
            windows.append(window)
        }
        return windows
    }

    /// タイトルでウィンドウを検索
    ///
    /// - Parameters:
    ///   - appElement: アプリの AXUIElement
    ///   - title: ウィンドウタイトル（部分一致、nil の場合は最初のウィンドウ）
    /// - Returns: マッチしたウィンドウの AXUIElement
    static func findWindow(app appElement: AXUIElement, title: String?) -> AXUIElement? {
        let allWindows = windows(for: appElement)

        guard let title else {
            return allWindows.first
        }

        return allWindows.first { window in
            guard let windowTitle: String = getAttribute(window, kAXTitleAttribute) else {
                return false
            }
            return windowTitle.localizedCaseInsensitiveContains(title)
        }
    }

    // MARK: - Window Position & Size

    /// ウィンドウの位置を取得
    static func windowPosition(_ window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return point
    }

    /// ウィンドウのサイズを取得
    static func windowSize(_ window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }
        var size = CGSize.zero
        AXValueGetValue(axValue as! AXValue, .cgSize, &size)
        return size
    }

    /// ウィンドウを移動
    @discardableResult
    static func moveWindow(_ window: AXUIElement, to point: CGPoint) -> AXError {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// ウィンドウをリサイズ
    @discardableResult
    static func resizeWindow(_ window: AXUIElement, to size: CGSize) -> AXError {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    // MARK: - Window Actions

    /// ウィンドウの最小化状態を設定
    @discardableResult
    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> AXError {
        setAttribute(window, kAXMinimizedAttribute, minimized as CFBoolean)
    }

    /// ウィンドウをフォーカス（Raise + アプリをアクティベート）
    @discardableResult
    static func focusWindow(_ window: AXUIElement) -> AXError {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

#endif
