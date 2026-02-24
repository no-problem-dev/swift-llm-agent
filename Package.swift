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
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "1.1.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
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
        ]),
        .target(name: "LLMAgentSession", dependencies: [
            "LLMAgent",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        .target(name: "LLMToolkits", dependencies: [
            "LLMAgent",
            "LLMMCP",
            .product(name: "LLMClient", package: "swift-llm-client"),
            .product(name: "LLMTool", package: "swift-llm-client"),
        ]),
        // Tests
        .testTarget(name: "LLMAgentTests", dependencies: ["LLMAgent"]),
        .testTarget(name: "LLMMCPTests", dependencies: ["LLMMCP"]),
        .testTarget(name: "LLMAgentSessionTests", dependencies: ["LLMAgentSession"]),
    ]
)
