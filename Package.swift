// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-agent",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LLMAgent", targets: ["LLMAgent"]),
        .library(name: "LLMMCP", targets: ["LLMMCP"]),
        .library(name: "LLMA2A", targets: ["LLMA2A"]),
        .library(name: "LLMAgentSession", targets: ["LLMAgentSession"]),
        .library(name: "LLMProject", targets: ["LLMProject"]),
        .library(name: "LLMToolkits", targets: ["LLMToolkits"]),
        .library(name: "LLMiOSToolkits", targets: ["LLMiOSToolkits"]),
        .library(name: "LLMmacOSToolkits", targets: ["LLMmacOSToolkits"]),
        .library(name: "LLMSubAgent", targets: ["LLMSubAgent"]),
        .library(name: "LLMSkill", targets: ["LLMSkill"]),
        .library(name: "LLMA2UI", targets: ["LLMA2UI"]),
        .library(name: "LLMA2UIChat", targets: ["LLMA2UIChat"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-agent-communication.git", from: "1.1.0"),
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "2.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-a2a.git", from: "0.1.1"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/no-problem-dev/swift-a2ui.git", from: "0.6.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(name: "LLMAgent", dependencies: [
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMMCP", dependencies: [
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "SwiftSoup", package: "SwiftSoup"),
        ]),
        .target(name: "LLMAgentSession", dependencies: [
            "LLMAgent",
            .product(name: "AgentCommunication", package: "swift-agent-communication"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMProject", dependencies: [
            "LLMMCP",  // ToolKit, BuiltInTool の定義元（将来 LLMTool に移動予定）
            "LLMAgent",
            "LLMAgentSession",
            .product(name: "AgentCommunication", package: "swift-agent-communication"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMToolkits", dependencies: [
            "LLMAgent",
            "LLMAgentSession",
            "LLMMCP",
            "LLMA2A",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMiOSToolkits", dependencies: [
            "LLMMCP",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMmacOSToolkits", dependencies: [
            "LLMMCP",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMSubAgent", dependencies: [
            "LLMAgent",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(
            name: "LLMSkill",
            dependencies: [
                "LLMAgent",
                "LLMSubAgent",
                .product(name: "LLMClient", package: "swift-llm-client"),
                .product(name: "LLMTool", package: "swift-llm-client"),
            ],
            resources: [
                .copy("Resources/InteractiveSkills"),
            ]
        ),
        .target(name: "LLMA2UI", dependencies: [
            "LLMAgent",
            .product(name: "A2UICore", package: "swift-a2ui"),
            .product(name: "A2UIParser", package: "swift-a2ui"),
            .product(name: "A2UIPrompt", package: "swift-a2ui"),
            .product(name: "A2UISurface", package: "swift-a2ui"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMA2UIChat", dependencies: [
            "LLMA2UI",
            "LLMAgent",
            .product(name: "A2UICore", package: "swift-a2ui"),
            .product(name: "A2UIPrompt", package: "swift-a2ui"),
            .product(name: "A2UIPromptCompact", package: "swift-a2ui"),
            .product(name: "A2UISurface", package: "swift-a2ui"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMA2A", dependencies: [
            .product(name: "A2A", package: "swift-a2a"),
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        // Tests
        .testTarget(name: "LLMAgentTests", dependencies: ["LLMAgent"]),
        .testTarget(name: "LLMMCPTests", dependencies: ["LLMMCP"]),
        .testTarget(name: "LLMA2UITests", dependencies: ["LLMA2UI"]),
        .testTarget(name: "LLMA2UIChatTests", dependencies: ["LLMA2UIChat"]),
        .testTarget(name: "LLMA2ATests", dependencies: ["LLMA2A"]),
        .testTarget(name: "LLMAgentSessionTests", dependencies: ["LLMAgentSession"]),
        .testTarget(name: "LLMProjectTests", dependencies: [
            "LLMProject",
            .product(name: "AgentCommunication", package: "swift-agent-communication"),
        ]),
        .testTarget(name: "LLMiOSToolkitsTests", dependencies: ["LLMiOSToolkits"]),
        .testTarget(name: "LLMmacOSToolkitsTests", dependencies: ["LLMmacOSToolkits"]),
        .testTarget(name: "LLMSubAgentTests", dependencies: ["LLMSubAgent"]),
        .testTarget(name: "LLMSkillTests", dependencies: ["LLMSkill", "LLMAgent"]),
    ]
)
