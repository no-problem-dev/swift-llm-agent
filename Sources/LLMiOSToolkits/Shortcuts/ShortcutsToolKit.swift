#if canImport(UIKit)
import Foundation
import LLMClient
import LLMTool
import LLMMCP
import UIKit

// MARK: - ShortcutsToolKit

/// Shortcuts アプリとの連携を提供する ToolKit
///
/// URL scheme を使用して、ショートカットの実行を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     ShortcutsToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `run_shortcut`: ショートカットを名前で実行
/// - `open_shortcuts`: Shortcuts アプリを開く
public final class ShortcutsToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "shortcuts"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            runShortcutTool,
            openShortcutsTool,
        ]
    }

    // MARK: - run_shortcut

    private var runShortcutTool: BuiltInTool {
        BuiltInTool(
            name: "run_shortcut",
            description: "Run a Shortcut by name. The Shortcuts app will open and execute the shortcut. "
                + "Note: The result of the shortcut execution cannot be captured programmatically.",
            inputSchema: .object(
                properties: [
                    "name": .string(description: "Name of the shortcut to run (exact match)"),
                    "input": .string(description: "Optional input text to pass to the shortcut"),
                ],
                required: ["name"]
            ),
            annotations: ToolAnnotations(
                title: "Run Shortcut",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: true
            )
        ) { data in
            struct Input: Codable {
                var name: String
                var input: String?
            }
            let input = try JSONDecoder().decode(Input.self, from: data)

            guard let encodedName = input.name.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) else {
                return .error("Invalid shortcut name.")
            }

            var urlString = "shortcuts://run-shortcut?name=\(encodedName)"
            if let inputText = input.input,
               let encodedInput = inputText.addingPercentEncoding(
                   withAllowedCharacters: .urlQueryAllowed
               ) {
                urlString += "&input=text&text=\(encodedInput)"
            }

            guard let url = URL(string: urlString) else {
                return .error("Failed to create shortcut URL.")
            }

            let opened = await MainActor.run {
                UIApplication.shared.canOpenURL(url)
            }

            guard opened else {
                return .error(
                    "Cannot open Shortcuts app. "
                    + "Make sure the Shortcuts app is installed."
                )
            }

            await MainActor.run {
                UIApplication.shared.open(url)
            }

            return .text("Shortcut '\(input.name)' launched. "
                + "Note: Execution happens in the Shortcuts app.")
        }
    }

    // MARK: - open_shortcuts

    private var openShortcutsTool: BuiltInTool {
        BuiltInTool(
            name: "open_shortcuts",
            description: "Open the Shortcuts app to browse available shortcuts.",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Open Shortcuts",
                readOnlyHint: true,
                openWorldHint: true
            )
        ) { _ in
            guard let url = URL(string: "shortcuts://") else {
                return .error("Failed to create Shortcuts URL.")
            }

            await MainActor.run {
                UIApplication.shared.open(url)
            }

            return .text("Shortcuts app opened.")
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// macOS 用のスタブ
public final class ShortcutsToolKit: ToolKit, Sendable {
    public let name: String = "shortcuts"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "run_shortcut",
                description: "Run a Shortcut by name. (iOS only)",
                inputSchema: .object(
                    properties: [
                        "name": .string(description: "Shortcut name"),
                        "input": .string(description: "Optional input"),
                    ],
                    required: ["name"]
                ),
                annotations: ToolAnnotations(openWorldHint: true)
            ) { _ in .error("ShortcutsToolKit URL scheme is only available on iOS.") },
            BuiltInTool(
                name: "open_shortcuts",
                description: "Open Shortcuts app. (iOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in .error("ShortcutsToolKit is only available on iOS.") },
        ]
    }
}
#endif
