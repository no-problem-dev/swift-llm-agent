// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-llm-agent",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LLMAgent", targets: ["LLMAgent"]),
        .library(name: "LLMMCP", targets: ["LLMMCP"]),
        .library(name: "LLMAgentSession", targets: ["LLMAgentSession"]),
        .library(name: "LLMToolkits", targets: ["LLMToolkits"]),
        .library(name: "LLMiOSToolkits", targets: ["LLMiOSToolkits"]),
        .library(name: "LLMSubAgent", targets: ["LLMSubAgent"]),
        .library(name: "LLMSkill", targets: ["LLMSkill"]),
    ],
    dependencies: [
        .package(path: "../swift-llm-client"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
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
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMToolkits", dependencies: [
            "LLMAgent",
            "LLMAgentSession",
            "LLMMCP",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMiOSToolkits", dependencies: [
            "LLMMCP",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMSubAgent", dependencies: [
            "LLMAgent",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMSkill", dependencies: [
            "LLMAgent",
            "LLMSubAgent",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        // Tests
        .testTarget(name: "LLMAgentTests", dependencies: ["LLMAgent"]),
        .testTarget(name: "LLMMCPTests", dependencies: ["LLMMCP"]),
        .testTarget(name: "LLMAgentSessionTests", dependencies: ["LLMAgentSession"]),
        .testTarget(name: "LLMiOSToolkitsTests", dependencies: ["LLMiOSToolkits"]),
        .testTarget(name: "LLMSubAgentTests", dependencies: ["LLMSubAgent"]),
        .testTarget(name: "LLMSkillTests", dependencies: ["LLMSkill"]),
    ]
)
