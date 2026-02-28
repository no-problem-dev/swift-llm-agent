#if os(macOS)

import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - SpotlightToolKit

/// Spotlight（mdfind）を使用したファイル検索ツールを提供する ToolKit
///
/// macOS の Spotlight メタデータインデックスを活用して、
/// ファイル名・内容・メタデータによる高速な全ディスク検索を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     SpotlightToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `spotlight_search`: Spotlight を使ったファイル検索
public final class SpotlightToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "spotlight"

    /// 最大結果件数の上限
    private let maxResultsLimit: Int

    /// デフォルトのタイムアウト（秒）
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// SpotlightToolKit を作成
    ///
    /// - Parameters:
    ///   - maxResultsLimit: 最大結果件数の上限（デフォルト: 100）
    ///   - timeout: mdfind のタイムアウト秒数（デフォルト: 15）
    public init(maxResultsLimit: Int = 100, timeout: TimeInterval = 15) {
        self.maxResultsLimit = maxResultsLimit
        self.timeout = timeout
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [spotlightSearchTool]
    }

    // MARK: - spotlight_search

    private var spotlightSearchTool: BuiltInTool {
        BuiltInTool(
            name: "spotlight_search",
            description: """
                Search files using macOS Spotlight. Searches file names, contents, \
                and metadata across the entire file system. Much faster than recursive \
                directory scanning for full-disk searches. \
                Supports Spotlight query syntax \
                (e.g., 'kMDItemContentType == "com.adobe.pdf"'). \
                For simple filename searches, just pass the filename or keyword. \
                Use the `directory` parameter to limit search scope.
                """,
            inputSchema: .object(
                properties: [
                    "query": .string(
                        description: "Search query. Can be a simple keyword or Spotlight query syntax."
                    ),
                    "directory": .string(
                        description: "Limit search to a specific directory path."
                    ),
                    "content_type": .string(
                        description: "Filter by file type: 'pdf', 'image', 'text', 'audio', 'video', 'folder', or a UTI (e.g., 'public.swift-source')."
                    ),
                    "max_results": .integer(
                        description: "Maximum number of results to return (default: 20)",
                        minimum: 1,
                        maximum: 100
                    ),
                ],
                required: ["query"]
            ),
            annotations: ToolAnnotations(
                title: "Spotlight Search",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(SpotlightSearchInput.self, from: data)
            let maxResults = min(input.maxResults ?? 20, maxResultsLimit)

            // mdfind コマンドを構築
            var arguments = [String]()

            if let directory = input.directory {
                arguments.append(contentsOf: ["-onlyin", directory])
            }

            // クエリを構築
            var query = input.query
            if let contentType = input.contentType {
                let uti = Self.resolveUTI(contentType)
                query = "(\(query)) && (kMDItemContentType == \"\(uti)\")"
            }

            arguments.append(query)

            let capturedArguments = arguments
            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask { [self] in
                    try await self.runMdfind(arguments: capturedArguments, maxResults: maxResults)
                }

                group.addTask { [self] in
                    try await Task.sleep(for: .seconds(self.timeout))
                    throw SpotlightToolKitError.timeout(seconds: self.timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - mdfind Execution

    private func runMdfind(arguments: [String], maxResults: Int) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SpotlightToolKitError.executionFailed(
                message: "Failed to run mdfind: \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return .error("Spotlight search failed: \(stderr)")
        }

        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        let allPaths = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        let paths = Array(allPaths.prefix(maxResults))
        let totalCount = allPaths.count

        // 各ファイルの基本情報を取得
        let fileManager = FileManager.default
        var results: [SpotlightResult] = []

        for path in paths {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }

            var size: Int64?
            var modified: String?
            if let attrs = try? fileManager.attributesOfItem(atPath: path) {
                size = attrs[.size] as? Int64
                if let date = attrs[.modificationDate] as? Date {
                    modified = ISO8601DateFormatter().string(from: date)
                }
            }

            results.append(SpotlightResult(
                path: path,
                name: (path as NSString).lastPathComponent,
                type: isDirectory.boolValue ? "directory" : "file",
                size: size,
                modified: modified
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let response = SpotlightSearchResponse(
            query: arguments.last ?? "",
            totalFound: totalCount,
            returned: results.count,
            truncated: totalCount > maxResults,
            results: results
        )

        let jsonData = try encoder.encode(response)
        let json = String(data: jsonData, encoding: .utf8) ?? "[]"
        return .text(json)
    }

    // MARK: - Helpers

    /// 簡易的なコンテンツタイプ名を UTI に解決
    private static func resolveUTI(_ type: String) -> String {
        switch type.lowercased() {
        case "pdf":
            return "com.adobe.pdf"
        case "image":
            return "public.image"
        case "text":
            return "public.plain-text"
        case "audio":
            return "public.audio"
        case "video":
            return "public.movie"
        case "folder", "directory":
            return "public.folder"
        case "swift":
            return "public.swift-source"
        case "json":
            return "public.json"
        case "markdown", "md":
            return "net.daringfireball.markdown"
        default:
            // UTI がそのまま渡された場合
            return type
        }
    }
}

// MARK: - Input Types

private struct SpotlightSearchInput: Codable {
    var query: String
    var directory: String?
    var contentType: String?
    var maxResults: Int?

    enum CodingKeys: String, CodingKey {
        case query, directory
        case contentType = "content_type"
        case maxResults = "max_results"
    }
}

// MARK: - Output Types

private struct SpotlightSearchResponse: Codable {
    var query: String
    var totalFound: Int
    var returned: Int
    var truncated: Bool
    var results: [SpotlightResult]

    enum CodingKeys: String, CodingKey {
        case query
        case totalFound = "total_found"
        case returned, truncated, results
    }
}

private struct SpotlightResult: Codable {
    var path: String
    var name: String
    var type: String
    var size: Int64?
    var modified: String?
}

// MARK: - Errors

public enum SpotlightToolKitError: Error, LocalizedError {
    case timeout(seconds: TimeInterval)
    case executionFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Spotlight search timed out after \(Int(seconds)) seconds"
        case .executionFailed(let message):
            return message
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（mdfind は macOS のみ）
public final class SpotlightToolKit: ToolKit, Sendable {
    public let name: String = "spotlight"
    public init(maxResultsLimit: Int = 100, timeout: TimeInterval = 15) {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "spotlight_search",
                description: "Search files using macOS Spotlight. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "query": .string(description: "Search query"),
                    ],
                    required: ["query"]
                ),
                annotations: .readOnly
            ) { _ in
                .error("SpotlightToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
