import Testing
@testable import LLMSubAgent
import LLMTool
import LLMAgent

// MARK: - SubAgentCatalog Tests

@Test func testCatalogBuilderWithMultipleTypes() {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(
            name: "researcher",
            description: "Research agent"
        )
        SubAgentTypeDefinition(
            name: "writer",
            description: "Writing agent"
        )
    }

    #expect(catalog.agentTypes.count == 2)
    #expect(catalog.agentTypeNames == ["researcher", "writer"])
}

@Test func testCatalogLookupByName() {
    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(
            name: "researcher",
            description: "Research agent"
        )
        SubAgentTypeDefinition(
            name: "writer",
            description: "Writing agent"
        )
    }

    let researcher = catalog.agentType(named: "researcher")
    #expect(researcher != nil)
    #expect(researcher?.name == "researcher")
    #expect(researcher?.description == "Research agent")

    let unknown = catalog.agentType(named: "nonexistent")
    #expect(unknown == nil)
}

@Test func testCatalogBuilderConditional() {
    let enableResearch = true
    let enableWriter = false

    let catalog = SubAgentCatalogDefinition {
        SubAgentTypeDefinition(name: "base", description: "Base agent")

        if enableResearch {
            SubAgentTypeDefinition(name: "researcher", description: "Research agent")
        }

        if enableWriter {
            SubAgentTypeDefinition(name: "writer", description: "Writing agent")
        }
    }

    #expect(catalog.agentTypes.count == 2)
    #expect(catalog.agentTypeNames == ["base", "researcher"])
}

@Test func testCatalogBuilderWithLoop() {
    let names = ["agent_a", "agent_b", "agent_c"]

    let catalog = SubAgentCatalogDefinition {
        for name in names {
            SubAgentTypeDefinition(name: name, description: "Agent \(name)")
        }
    }

    #expect(catalog.agentTypes.count == 3)
    #expect(catalog.agentTypeNames == ["agent_a", "agent_b", "agent_c"])
}

@Test func testCatalogFromArray() {
    let types: [any SubAgentType] = [
        SubAgentTypeDefinition(name: "a", description: "A"),
        SubAgentTypeDefinition(name: "b", description: "B"),
    ]

    let catalog = SubAgentCatalogDefinition(agentTypes: types)
    #expect(catalog.agentTypes.count == 2)
}

@Test func testEmptyCatalog() {
    let catalog = SubAgentCatalogDefinition { }

    #expect(catalog.agentTypes.isEmpty)
    #expect(catalog.agentTypeNames.isEmpty)
    #expect(catalog.agentType(named: "anything") == nil)
}

// MARK: - SubAgentTypeDefinition Tests

@Test func testTypeDefinitionDefaults() {
    let agentType = SubAgentTypeDefinition(
        name: "test",
        description: "Test agent"
    )

    #expect(agentType.name == "test")
    #expect(agentType.description == "Test agent")
    #expect(agentType.tools.isEmpty)
    #expect(agentType.systemPrompt == nil)
    #expect(agentType.configuration.maxSteps == AgentConfiguration.default.maxSteps)
}

@Test func testTypeDefinitionCustomConfiguration() {
    let config = AgentConfiguration(maxSteps: 20)

    let agentType = SubAgentTypeDefinition(
        name: "custom",
        description: "Custom agent",
        configuration: config
    )

    #expect(agentType.configuration.maxSteps == 20)
}
