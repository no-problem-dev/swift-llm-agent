#if os(macOS)

import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - ShellToolKit

/// シェルコマンド実行ツールを提供する ToolKit
///
/// `Process` クラスを使用して `/bin/zsh` でシェルコマンドを実行します。
/// タイムアウト付きの非同期実行をサポートし、stdout/stderr をキャプチャして返します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     ShellToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `execute_shell`: シェルコマンドを実行し、結果を返す
public final class ShellToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "shell"

    /// 最大出力文字数
    private let maxOutputLength: Int

    /// デフォルトタイムアウト（秒）
    private let defaultTimeout: TimeInterval

    // MARK: - Initialization

    /// ShellToolKit を作成
    ///
    /// - Parameters:
    ///   - maxOutputLength: 出力の最大文字数（デフォルト: 50,000）
    ///   - defaultTimeout: デフォルトのタイムアウト秒数（デフォルト: 30）
    public init(
        maxOutputLength: Int = 50_000,
        defaultTimeout: TimeInterval = 30
    ) {
        self.maxOutputLength = maxOutputLength
        self.defaultTimeout = defaultTimeout
    }

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [executeShellTool]
    }

    // MARK: - execute_shell

    private var executeShellTool: BuiltInTool {
        BuiltInTool(
            name: "execute_shell",
            description: """
                Execute a shell command using /bin/zsh and return the output. \
                Use this for system operations, file manipulation, package management, \
                git commands, and any task that requires shell access. \
                stdout and stderr are captured and returned. \
                Long output is truncated, keeping the tail (most recent output).
                """,
            inputSchema: .object(
                properties: [
                    "command": .string(
                        description: "Shell command to execute"
                    ),
                    "working_directory": .string(
                        description: "Working directory for the command. Defaults to the current directory."
                    ),
                    "timeout": .integer(
                        description: "Timeout in seconds (default: 30, max: 300)",
                        minimum: 1,
                        maximum: 300
                    ),
                ],
                required: ["command"]
            ),
            annotations: ToolAnnotations(
                title: "Execute Shell",
                readOnlyHint: false,
                destructiveHint: true,
                openWorldHint: true
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(ExecuteShellInput.self, from: data)
            let timeout = min(TimeInterval(input.timeout ?? Int(defaultTimeout)), 300)

            return try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask { [self] in
                    try await self.executeCommand(
                        command: input.command,
                        workingDirectory: input.workingDirectory
                    )
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw ShellToolKitError.timeout(seconds: timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }

    // MARK: - Command Execution

    private func executeCommand(
        command: String,
        workingDirectory: String?
    ) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let workingDirectory {
            let url = URL(fileURLWithPath: workingDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .error("Working directory does not exist: \(workingDirectory)")
            }
            process.currentDirectoryURL = url
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellToolKitError.executionFailed(message: error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        var output = ""

        if !stdout.isEmpty {
            output += stdout
        }

        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "[stderr]\n\(stderr)"
        }

        if output.isEmpty {
            output = "(no output)"
        }

        // 長い出力は末尾を優先して切り詰め
        if output.count > maxOutputLength {
            let truncated = String(output.suffix(maxOutputLength))
            output = "[output truncated, showing last \(maxOutputLength) characters]\n\(truncated)"
        }

        if exitCode != 0 {
            output += "\n[exit code: \(exitCode)]"
        }

        return .text(output)
    }
}

// MARK: - Input Types

private struct ExecuteShellInput: Codable {
    var command: String
    var workingDirectory: String?
    var timeout: Int?

    enum CodingKeys: String, CodingKey {
        case command
        case workingDirectory = "working_directory"
        case timeout
    }
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（Process は macOS のみ）
public final class ShellToolKit: ToolKit, Sendable {
    public let name: String = "shell"
    public init(maxOutputLength: Int = 50_000, defaultTimeout: TimeInterval = 30) {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "execute_shell",
                description: "Execute a shell command. (macOS only)",
                inputSchema: .object(
                    properties: [
                        "command": .string(description: "Shell command to execute"),
                    ],
                    required: ["command"]
                ),
                annotations: .destructive
            ) { _ in
                .error("ShellToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
