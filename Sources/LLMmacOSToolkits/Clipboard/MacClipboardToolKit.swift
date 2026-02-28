#if os(macOS)

import AppKit
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - MacClipboardToolKit

/// macOS のクリップボード（ペーストボード）を操作する ToolKit
///
/// `NSPasteboard` を使用して、クリップボードの読み書きを提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     MacClipboardToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `mac_get_clipboard`: クリップボードのテキスト内容を読み取り
/// - `mac_set_clipboard`: テキストをクリップボードにコピー
public final class MacClipboardToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "mac-clipboard"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            getClipboardTool,
            setClipboardTool,
        ]
    }

    // MARK: - get_clipboard

    private var getClipboardTool: BuiltInTool {
        BuiltInTool(
            name: "mac_get_clipboard",
            description: "Read the current text content from the macOS clipboard (pasteboard).",
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "Get Clipboard",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            if let text = NSPasteboard.general.string(forType: .string) {
                return .text(text)
            } else {
                return .text("(clipboard is empty or does not contain text)")
            }
        }
    }

    // MARK: - set_clipboard

    private var setClipboardTool: BuiltInTool {
        BuiltInTool(
            name: "mac_set_clipboard",
            description: "Copy text to the macOS clipboard (pasteboard).",
            inputSchema: .object(
                properties: [
                    "text": .string(description: "Text to copy to the clipboard"),
                ],
                required: ["text"]
            ),
            annotations: ToolAnnotations(
                title: "Set Clipboard",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { data in
            struct Input: Codable { var text: String }
            let input = try JSONDecoder().decode(Input.self, from: data)

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(input.text, forType: .string)

            return .text("Text copied to clipboard (\(input.text.count) characters).")
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（NSPasteboard は macOS のみ）
public final class MacClipboardToolKit: ToolKit, Sendable {
    public let name: String = "mac-clipboard"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "mac_get_clipboard",
                description: "Read the current text content from the clipboard. (macOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                .error("MacClipboardToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "mac_set_clipboard",
                description: "Copy text to the clipboard. (macOS only)",
                inputSchema: .object(
                    properties: ["text": .string(description: "Text to copy")],
                    required: ["text"]
                ),
                annotations: .idempotentWrite
            ) { _ in
                .error("MacClipboardToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
