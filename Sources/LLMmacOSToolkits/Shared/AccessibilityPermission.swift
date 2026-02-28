#if os(macOS)

import ApplicationServices
import Foundation

// MARK: - AccessibilityPermission

/// Accessibility 権限の確認とガイダンスメッセージ生成
enum AccessibilityPermission {

    /// Accessibility 権限が付与されているかチェック
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 権限がない場合にプロンプトを表示してチェック
    ///
    /// - Returns: 権限が付与されていれば true
    static func checkWithPrompt() -> Bool {
        // kAXTrustedCheckOptionPrompt は extern CFStringRef のため
        // strict concurrency で shared mutable state 扱いになる。文字列リテラルで回避。
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 権限不足時のガイダンスメッセージ
    static let permissionGuide = """
        Accessibility permission is required. \
        Grant access in System Settings > Privacy & Security > Accessibility. \
        Add this application to the allowed list, then retry.
        """
}

#endif
