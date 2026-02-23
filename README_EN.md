English | [日本語](README.md)

# LLMAgent

An LLM agent architecture Swift package

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Features

- **Agent Architecture** - Autonomous LLM agents with tool execution loops
- **MCP Integration** - Tool server connectivity via Model Context Protocol
- **Session Management** - Conversation state persistence and restoration
- **Toolkits** - Reusable tool sets for common operations

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-agent.git", .upToNextMajor(from: "1.0.0"))
]
```

### Module Structure

Import only the modules you need:

| Module | Purpose |
|--------|---------|
| `LLMAgent` | Agent core (execution loop, tool management) |
| `LLMMCP` | Model Context Protocol integration |
| `LLMAgentSession` | Session management (state persistence, restoration) |
| `LLMToolkits` | Reusable tool kits |

## Quick Start

### Creating an Agent

```swift
import LLMAgent

let agent = Agent(
    provider: provider,  // any LLMProvider
    tools: toolSet       // ToolSet
)

// Run agent (automatically handles tool calls)
let response = try await agent.run(
    messages: [.user("Create a README for the project")]
)
```

### MCP Server Integration

```swift
import LLMMCP

let mcpClient = MCPToolProvider(
    serverCommand: "npx",
    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
)

let tools = try await mcpClient.tools()
```

### Session Management

```swift
import LLMAgentSession

let session = AgentSession(agent: agent)

// Save and restore sessions
try await session.save(to: sessionURL)
let restored = try await AgentSession.load(from: sessionURL, agent: agent)
```

## Documentation

See the DocC documentation for detailed guides and API reference.

| Guide | Description |
|-------|-------------|
| [API Reference](https://no-problem-dev.github.io/swift-llm-agent/documentation/llmagent/) | Full public API |

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## Dependencies

- [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) (>= 1.1.0) - LLM client abstraction
- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (>= 0.10.0) - Model Context Protocol SDK

## License

MIT License - See [LICENSE](LICENSE) for details

## Links

- [Full Documentation](https://no-problem-dev.github.io/swift-llm-agent/documentation/llmagent/)
- [Report Issues](https://github.com/no-problem-dev/swift-llm-agent/issues)
- [Discussions](https://github.com/no-problem-dev/swift-llm-agent/discussions)
- [Release Process](RELEASE_PROCESS.md)
