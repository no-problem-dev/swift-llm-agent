#if os(macOS)

import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - MacShortcutsToolKit

/// macOS Shortcuts アプリとの連携を提供する ToolKit
///
/// `shortcuts` CLI を使用して、ショートカットの一覧取得と実行を提供します。
/// iOS 版と異なり、実行結果を取得することができます。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     MacShortcutsToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `mac_list_shortcuts`: 利用可能なショートカットの一覧
/// - `mac_run_shortcut`: ショートカットを名前で実行し結果を取得
public final class MacShortcutsToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "shortcuts"

    /// タイムアウト（秒）
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// MacShortcutsToolKit を作成
    ///
    /// - Parameters:
    ///   - timeout: ショートカット実行のタイムアウト秒数（デフォルト: 60）
    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            listShortcutsTool,
            runShortcutTool,
        ]
    }

    // MARK: - list_shortcuts

    private var listShortcutsTool: BuiltInTool {
        BuiltInTool(
            name: "mac_list_shortcuts",
            description: """
                List all available Shortcuts on this Mac. \
                Returns shortcut names that can be used with run_shortcut.
                """,
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Shortcuts",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                return .error("Failed to run 'shortcuts list': \(error.localizedDescription)")
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: stdoutData, encoding: .utf8) ?? ""

            let shortcuts = output.components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            if shortcuts.isEmpty {
                return .text("No shortcuts found.")
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(ShortcutListOutput(
                count: shortcuts.count,
                shortcuts: shortcuts
            ))
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return .text(json)
        }
    }

    // MARK: - run_shortcut

    private var runShortcutTool: BuiltInTool {
        BuiltInTool(
            name: "mac_run_shortcut",
            description: """
                Run a Shortcut by name on macOS. Unlike iOS, the shortcut's output \
                can be captured and returned. Use list_shortcuts first to see available shortcuts.
                """,
            inputSchema: .object(
                properties: [
                    "name": .string(
                        description: "Name of the shortcut to run (exact match)"
                    ),
                    "input": .string(
                        description: "Optional input text to pass to the shortcut via stdin"
                    ),
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
        ) { [self] data in
            let input = try JSONDecoder().decode(RunShortcutInput.self, from: data)

            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask { [self] in
                    try await self.executeShortcut(
                        name: input.name,
                        inputText: input.input
                    )
                }

                group.addTask { [self] in
                    try await Task.sleep(for: .seconds(self.timeout))
                    throw MacShortcutsToolKitError.timeout(
                        shortcut: input.name,
                        seconds: self.timeout
                    )
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - Shortcut Execution

    private func executeShortcut(name: String, inputText: String?) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 入力テキストがあれば stdin に渡す
        if let inputText, let inputData = inputText.data(using: .utf8) {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(inputData)
            stdinPipe.fileHandleForWriting.closeFile()
        }

        do {
            try process.run()
        } catch {
            return .error(
                "Failed to run shortcut '\(name)': \(error.localizedDescription). "
                + "Make sure the shortcut exists (use list_shortcuts to check)."
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            return .error(
                "Shortcut '\(name)' failed with exit code \(process.terminationStatus). "
                + (stderr.isEmpty ? "" : "Error: \(stderr)")
            )
        }

        if stdout.isEmpty && stderr.isEmpty {
            return .text("Shortcut '\(name)' completed successfully (no output).")
        }

        var output = ""
        if !stdout.isEmpty {
            output = stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "[stderr] \(stderr)"
        }

        return .text(output)
    }
}

// MARK: - Input Types

private struct RunShortcutInput: Codable {
    var name: String
    var input: String?
}

// MARK: - Output Types

private struct ShortcutListOutput: Codable {
    var count: Int
    var shortcuts: [String]
}

// MARK: - Errors

public enum MacShortcutsToolKitError: Error, LocalizedError {
    case timeout(shortcut: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timeout(let shortcut, let seconds):
            return "Shortcut '\(shortcut)' timed out after \(Int(seconds)) seconds"
        }
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（shortcuts CLI は macOS のみ）
public final class MacShortcutsToolKit: ToolKit, Sendable {
    public let name: String = "shortcuts"
    public init(timeout: TimeInterval = 60) {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "mac_list_shortcuts",
                description: "List all available Shortcuts. (macOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                .error("MacShortcutsToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "mac_run_shortcut",
                description: "Run a Shortcut by name. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "name": .string(description: "Shortcut name"),
                    ],
                    required: ["name"]
                ),
                annotations: ToolAnnotations(openWorldHint: true)
            ) { _ in
                .error("MacShortcutsToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
