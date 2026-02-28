#if os(macOS)

import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - FileTagToolKit

/// macOS Finder タグの読み書きツールを提供する ToolKit
///
/// `URL.resourceValues` を使用して、ファイルやディレクトリの
/// Finder タグ（カラーラベル）を読み取り・設定します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     FileTagToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `get_file_tags`: ファイル/ディレクトリの Finder タグを取得
/// - `set_file_tags`: ファイル/ディレクトリの Finder タグを設定
public final class FileTagToolKit: ToolKit, Sendable {

    // MARK: - Properties

    public let name: String = "file-tag"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            getFileTagsTool,
            setFileTagsTool,
        ]
    }

    // MARK: - get_file_tags

    private var getFileTagsTool: BuiltInTool {
        BuiltInTool(
            name: "get_file_tags",
            description: """
                Read macOS Finder tags for a file or directory. \
                Returns the list of tag names (e.g., "Red", "Work", "Important").
                """,
            inputSchema: .object(
                properties: [
                    "path": .string(
                        description: "Absolute path to the file or directory"
                    ),
                ],
                required: ["path"]
            ),
            annotations: ToolAnnotations(
                title: "Get File Tags",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(FileTagInput.self, from: data)
            let url = URL(fileURLWithPath: input.path)

            guard FileManager.default.fileExists(atPath: input.path) else {
                return .error("File not found: \(input.path)")
            }

            let resourceValues = try url.resourceValues(forKeys: [.tagNamesKey])
            let tags = resourceValues.tagNames ?? []

            let output = FileTagOutput(path: input.path, tags: tags)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(output)
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }

    // MARK: - set_file_tags

    private var setFileTagsTool: BuiltInTool {
        BuiltInTool(
            name: "set_file_tags",
            description: """
                Set macOS Finder tags for a file or directory. \
                Replaces all existing tags with the provided list. \
                Pass an empty array to clear all tags. \
                Common built-in color tags: "Red", "Orange", "Yellow", \
                "Green", "Blue", "Purple", "Gray". \
                Custom tags can be any string.
                """,
            inputSchema: .object(
                properties: [
                    "path": .string(
                        description: "Absolute path to the file or directory"
                    ),
                    "tags": .array(
                        description: "Array of tag names to set",
                        items: .string()
                    ),
                ],
                required: ["path", "tags"]
            ),
            annotations: ToolAnnotations(
                title: "Set File Tags",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ) { data in
            let input = try JSONDecoder().decode(SetFileTagInput.self, from: data)

            guard FileManager.default.fileExists(atPath: input.path) else {
                return .error("File not found: \(input.path)")
            }

            // xattr を使ってタグを設定（URLResourceValues.tagNames setter は macOS 26+ のため）
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: input.tags,
                format: .binary,
                options: 0
            )
            // com.apple.metadata:_kMDItemUserTags 拡張属性として設定
            let result = input.path.withCString { pathPtr in
                plistData.withUnsafeBytes { buffer in
                    setxattr(
                        pathPtr,
                        "com.apple.metadata:_kMDItemUserTags",
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        0
                    )
                }
            }
            guard result == 0 else {
                return .error(
                    "Failed to set tags on \(input.path): "
                    + String(cString: strerror(errno))
                )
            }

            if input.tags.isEmpty {
                return .text("Cleared all tags from \(input.path)")
            }

            return .text(
                "Set \(input.tags.count) tag(s) on \(input.path): "
                + input.tags.joined(separator: ", ")
            )
        }
    }
}

// MARK: - Input Types

private struct FileTagInput: Codable {
    var path: String
}

private struct SetFileTagInput: Codable {
    var path: String
    var tags: [String]
}

// MARK: - Output Types

private struct FileTagOutput: Codable {
    var path: String
    var tags: [String]
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（Finder タグは macOS のみ）
public final class FileTagToolKit: ToolKit, Sendable {
    public let name: String = "file-tag"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "get_file_tags",
                description: "Read macOS Finder tags. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "path": .string(description: "File path"),
                    ],
                    required: ["path"]
                ),
                annotations: .readOnly
            ) { _ in
                .error("FileTagToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "set_file_tags",
                description: "Set macOS Finder tags. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "path": .string(description: "File path"),
                        "tags": .array(description: "Tag names", items: .string()),
                    ],
                    required: ["path", "tags"]
                ),
                annotations: .idempotentWrite
            ) { _ in
                .error("FileTagToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
