#if os(macOS)

import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - AppleScriptToolKit

/// AppleScript / JXA スクリプト実行ツールを提供する ToolKit
///
/// 他の専用ツールでカバーできない macOS 自動化タスクのフォールバックとして使用します。
/// AppleScript（`NSAppleScript`）と JXA（`osascript -l JavaScript`）の両方に対応。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     AppleScriptToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `run_applescript`: AppleScript コードを実行
/// - `run_jxa`: JavaScript for Automation (JXA) コードを実行
public final class AppleScriptToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "applescript"

    /// デフォルトタイムアウト（秒）
    private let defaultTimeout: Int

    /// 最大出力文字数
    private let maxOutputLength: Int

    // MARK: - Initialization

    /// AppleScriptToolKit を作成
    ///
    /// - Parameters:
    ///   - defaultTimeout: デフォルトのタイムアウト秒数（デフォルト: 30）
    ///   - maxOutputLength: 出力の最大文字数（デフォルト: 50,000）
    public init(defaultTimeout: Int = 30, maxOutputLength: Int = 50_000) {
        self.defaultTimeout = defaultTimeout
        self.maxOutputLength = maxOutputLength
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [runAppleScriptTool, runJXATool]
    }

    // MARK: - run_applescript

    private var runAppleScriptTool: BuiltInTool {
        BuiltInTool(
            name: "run_applescript",
            description: """
                Execute an AppleScript script on macOS. \
                Use for controlling scriptable apps (Finder, Safari, Mail, etc.) \
                or tasks not covered by dedicated tools. \
                Prefer dedicated tools (app_launch, spotlight_search) when available, \
                as they produce structured output. \
                Requires Apple Events permission (prompted on first use per target app).
                """,
            inputSchema: .object(
                properties: [
                    "script": .string(
                        description: "AppleScript source code to execute"
                    ),
                    "timeout": .integer(
                        description: "Timeout in seconds (default: 30, max: 120)",
                        minimum: 1,
                        maximum: 120
                    ),
                ],
                required: ["script"]
            ),
            annotations: ToolAnnotations(
                title: "Run AppleScript",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: true
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(ScriptInput.self, from: data)
            let timeout = min(input.timeout ?? defaultTimeout, 120)

            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask {
                    try await self.executeAppleScript(source: input.script)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw AppleScriptToolKitError.timeout(seconds: timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - run_jxa

    private var runJXATool: BuiltInTool {
        BuiltInTool(
            name: "run_jxa",
            description: """
                Execute JavaScript for Automation (JXA) code on macOS. \
                JXA provides JavaScript syntax for macOS automation. \
                Use JSON.stringify(result) as the last expression to get structured output. \
                console.log() output goes to stderr and is captured separately.
                """,
            inputSchema: .object(
                properties: [
                    "script": .string(
                        description: "JXA (JavaScript for Automation) source code to execute"
                    ),
                    "timeout": .integer(
                        description: "Timeout in seconds (default: 30, max: 120)",
                        minimum: 1,
                        maximum: 120
                    ),
                ],
                required: ["script"]
            ),
            annotations: ToolAnnotations(
                title: "Run JXA",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: true
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(ScriptInput.self, from: data)
            let timeout = min(input.timeout ?? defaultTimeout, 120)

            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask { [self] in
                    try await self.executeJXA(source: input.script)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw AppleScriptToolKitError.timeout(seconds: timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - AppleScript Execution

    private func executeAppleScript(source: String) async throws -> ToolResult {
        let script = NSAppleScript(source: source)!
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Unknown AppleScript error"

            // errAEEventNotPermitted (-1743)
            if errorNumber == -1743 {
                let target = errorInfo[NSAppleScript.errorAppName] as? String
                throw AppleScriptToolKitError.permissionDenied(target: target)
            }

            return .error(errorMessage)
        }

        let output = descriptor.stringValue ?? "(no output)"
        return .text(truncateOutput(output))
    }

    // MARK: - JXA Execution

    private func executeJXA(source: String) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", source]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppleScriptToolKitError.executionFailed(message: error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        // errAEEventNotPermitted check
        if exitCode != 0 && stderr.contains("-1743") {
            throw AppleScriptToolKitError.permissionDenied(target: nil)
        }

        if exitCode != 0 {
            return .error("JXA execution failed (exit code \(exitCode)): \(stderr)")
        }

        var output = ""

        if !stdout.isEmpty {
            output += stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "[stderr]\n\(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        if output.isEmpty {
            output = "(no output)"
        }

        return .text(truncateOutput(output))
    }

    // MARK: - Helpers

    private func truncateOutput(_ output: String) -> String {
        if output.count > maxOutputLength {
            let truncated = String(output.suffix(maxOutputLength))
            return "[output truncated, showing last \(maxOutputLength) characters]\n\(truncated)"
        }
        return output
    }
}

// MARK: - Input Types

private struct ScriptInput: Codable {
    var script: String
    var timeout: Int?
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（AppleScript / JXA は macOS のみ）
public final class AppleScriptToolKit: ToolKit, Sendable {
    public let name: String = "applescript"
    public init(defaultTimeout: Int = 30, maxOutputLength: Int = 50_000) {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "run_applescript",
                description: "Execute an AppleScript script. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "script": .string(description: "AppleScript source code"),
                    ],
                    required: ["script"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false, openWorldHint: true)
            ) { _ in
                .error("AppleScriptToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "run_jxa",
                description: "Execute JXA (JavaScript for Automation) code. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "script": .string(description: "JXA source code"),
                    ],
                    required: ["script"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false, openWorldHint: true)
            ) { _ in
                .error("AppleScriptToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
