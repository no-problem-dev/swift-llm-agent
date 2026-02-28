#if os(macOS)

import AppKit
import Foundation
import LLMClient
import LLMTool
import LLMMCP

// MARK: - AppControlToolKit

/// macOS アプリケーションの制御ツールを提供する ToolKit
///
/// `NSWorkspace` を使用して、アプリケーションの一覧取得・起動・アクティベート・終了を提供します。
///
/// ## 使用例
///
/// ```swift
/// let tools = ToolSet {
///     AppControlToolKit()
/// }
/// ```
///
/// ## 提供されるツール
///
/// - `app_list_running`: 実行中のアプリケーション一覧を取得
/// - `app_launch`: アプリケーションを起動
/// - `app_activate`: アプリケーションを最前面に表示
/// - `app_quit`: アプリケーションを終了
public final class AppControlToolKit: ToolKit, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "app-control"

    // MARK: - Initialization

    public init() {}

    // MARK: - ToolKit Protocol

    public var tools: [any Tool] {
        [
            appListRunningTool,
            appLaunchTool,
            appActivateTool,
            appQuitTool,
        ]
    }

    // MARK: - app_list_running

    private var appListRunningTool: BuiltInTool {
        BuiltInTool(
            name: "app_list_running",
            description: """
                List all currently running applications on macOS. \
                Returns application name, bundle identifier, process ID, and active status. \
                Only shows regular applications (excludes background processes and agents).
                """,
            inputSchema: .object(
                properties: [:],
                required: []
            ),
            annotations: ToolAnnotations(
                title: "List Running Apps",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { _ in
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { RunningAppInfo(from: $0) }

            let data = try JSONEncoder().encode(apps)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return .text(json)
        }
    }

    // MARK: - app_launch

    private var appLaunchTool: BuiltInTool {
        BuiltInTool(
            name: "app_launch",
            description: """
                Launch an application on macOS. \
                You can specify the application by name (e.g., "Safari", "Xcode") \
                or by bundle identifier (e.g., "com.apple.Safari"). \
                The application will be searched in /Applications and its subdirectories.
                """,
            inputSchema: .object(
                properties: [
                    "name": .string(
                        description: "Application name (e.g., \"Safari\") or bundle identifier (e.g., \"com.apple.Safari\")"
                    ),
                    "hidden": .boolean(
                        description: "Launch the application hidden (default: false)"
                    ),
                ],
                required: ["name"]
            ),
            annotations: ToolAnnotations(
                title: "Launch App",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: true
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(AppLaunchInput.self, from: data)

            guard let appURL = resolveAppURL(name: input.name) else {
                return .error("Application not found: \(input.name)")
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = !(input.hidden ?? false)
            configuration.hides = input.hidden ?? false

            do {
                let app = try await NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: configuration
                )
                let appName = app.localizedName ?? input.name
                return .text("Launched \(appName) (PID: \(app.processIdentifier)).")
            } catch {
                return .error("Failed to launch \(input.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - app_activate

    private var appActivateTool: BuiltInTool {
        BuiltInTool(
            name: "app_activate",
            description: """
                Bring a running application to the foreground on macOS. \
                The application must already be running. \
                You can specify the application by name or bundle identifier.
                """,
            inputSchema: .object(
                properties: [
                    "name": .string(
                        description: "Application name or bundle identifier"
                    ),
                ],
                required: ["name"]
            ),
            annotations: ToolAnnotations(
                title: "Activate App",
                readOnlyHint: false,
                destructiveHint: false,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(AppNameInput.self, from: data)

            guard let app = findRunningApp(name: input.name) else {
                return .error("Running application not found: \(input.name)")
            }

            let success = app.activate()
            let appName = app.localizedName ?? input.name

            if success {
                return .text("Activated \(appName).")
            } else {
                return .error("Failed to activate \(appName).")
            }
        }
    }

    // MARK: - app_quit

    private var appQuitTool: BuiltInTool {
        BuiltInTool(
            name: "app_quit",
            description: """
                Quit a running application on macOS. \
                By default, sends a graceful termination request. \
                Use force=true to force-quit the application.
                """,
            inputSchema: .object(
                properties: [
                    "name": .string(
                        description: "Application name or bundle identifier"
                    ),
                    "force": .boolean(
                        description: "Force-quit the application (default: false)"
                    ),
                ],
                required: ["name"]
            ),
            annotations: ToolAnnotations(
                title: "Quit App",
                readOnlyHint: false,
                destructiveHint: true,
                openWorldHint: false
            )
        ) { [self] data in
            let input = try JSONDecoder().decode(AppQuitInput.self, from: data)

            guard let app = findRunningApp(name: input.name) else {
                return .error("Running application not found: \(input.name)")
            }

            let appName = app.localizedName ?? input.name
            let success: Bool

            if input.force ?? false {
                success = app.forceTerminate()
            } else {
                success = app.terminate()
            }

            if success {
                let method = (input.force ?? false) ? "Force-quit" : "Quit"
                return .text("\(method) \(appName).")
            } else {
                return .error("Failed to quit \(appName).")
            }
        }
    }

    // MARK: - Helpers

    /// アプリ名またはバンドルIDから URL を解決
    private func resolveAppURL(name: String) -> URL? {
        // バンドルID として試す
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return url
        }

        // アプリ名として /Applications 配下を探索
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]

        for searchPath in searchPaths {
            let appURL = URL(fileURLWithPath: searchPath).appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: appURL.path) {
                return appURL
            }
        }

        return nil
    }

    /// 実行中のアプリを名前またはバンドルIDで検索
    private func findRunningApp(name: String) -> NSRunningApplication? {
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
}

#else

import Foundation
import LLMClient
import LLMTool
import LLMMCP

/// iOS 用のスタブ（NSWorkspace は macOS のみ）
public final class AppControlToolKit: ToolKit, Sendable {
    public let name: String = "app-control"
    public init() {}

    public var tools: [any Tool] {
        [
            BuiltInTool(
                name: "app_list_running",
                description: "List running applications. (macOS only)",
                inputSchema: .object(properties: [:], required: []),
                annotations: .readOnly
            ) { _ in
                .error("AppControlToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "app_launch",
                description: "Launch an application. (macOS only)",
                inputSchema: .object(
                    properties: ["name": .string(description: "Application name")],
                    required: ["name"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false, openWorldHint: true)
            ) { _ in
                .error("AppControlToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "app_activate",
                description: "Activate a running application. (macOS only)",
                inputSchema: .object(
                    properties: ["name": .string(description: "Application name")],
                    required: ["name"]
                ),
                annotations: ToolAnnotations(readOnlyHint: false)
            ) { _ in
                .error("AppControlToolKit is only available on macOS.")
            },
            BuiltInTool(
                name: "app_quit",
                description: "Quit an application. (macOS only)",
                inputSchema: .object(
                    properties: ["name": .string(description: "Application name")],
                    required: ["name"]
                ),
                annotations: .destructive
            ) { _ in
                .error("AppControlToolKit is only available on macOS.")
            },
        ]
    }
}

#endif
