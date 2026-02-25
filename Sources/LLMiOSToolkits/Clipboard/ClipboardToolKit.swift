#if canImport(UIKit)
import Foundation
import LLMClient
import LLMTool
import LLMMCP
import UIKit

// MARK: - ClipboardToolKit

/// クリップボード（ペーストボード）を操作する ToolKit
///
/// UIPasteboard を使用して、クリップボードの読み書きを提供します。
/// iOS 16+ ではペースト時にシステムの確認バナーが自動表示されます。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     ClipboardToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_clipboard`: クリップボードのテキスト内容を読み取り
/// - `set_clipboard`: テキストをクリップボードにコピー
public final class ClipboardToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "clipboard"

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
            name: "get_clipboard",
            description: "Read the current text content from the clipboard (pasteboard). "
                + "Note: On iOS 16+, the system will show a paste confirmation to the user.",
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
            if let text = await MainActor.run(body: { UIPasteboard.general.string }) {
                return .text(text)
            } else {
                return .text("(clipboard is empty or does not contain text)")
            }
        }
    }

    // MARK: - set_clipboard

    private var setClipboardTool: BuiltInTool {
        BuiltInTool(
            name: "set_clipboard",
            description: "Copy text to the clipboard (pasteboard).",
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

            await MainActor.run { UIPasteboard.general.string = input.text }

            return .text("Text copied to clipboard (\(input.text.count) characters).")
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// macOS 用のスタブ（UIPasteboard は iOS のみ）
public final class ClipboardToolKit: ToolKit, Sendable {
    public let name: String = "clipboard"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "get_clipboard",
                description: "Read the current text content from the clipboard. (iOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                .error("ClipboardToolKit is only available on iOS/iPadOS.")
            },
            BuiltInTool(
                name: "set_clipboard",
                description: "Copy text to the clipboard. (iOS only)",
                inputSchema: .object(
                    properties: ["text": .string(description: "Text to copy")],
                    required: ["text"]
                ),
                annotations: .idempotentWrite
            ) { _ in
                .error("ClipboardToolKit is only available on iOS/iPadOS.")
            },
        ]
    }
}

#endif
