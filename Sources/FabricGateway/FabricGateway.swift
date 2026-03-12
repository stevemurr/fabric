import Foundation
import Fabric

public struct FabricMCPServerInfo: Codable, Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct FabricMCPInitializeResponse: Codable, Sendable, Equatable {
    public let protocolVersion: String
    public let capabilities: FabricMetadata
    public let serverInfo: FabricMCPServerInfo

    public init(
        protocolVersion: String,
        capabilities: FabricMetadata,
        serverInfo: FabricMCPServerInfo
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

public struct FabricMCPResource: Codable, Sendable, Equatable {
    public let uri: String
    public let name: String
    public let title: String
    public let description: String
    public let metadata: FabricMetadata

    public init(
        uri: String,
        name: String,
        title: String,
        description: String,
        metadata: FabricMetadata
    ) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.metadata = metadata
    }
}

public struct FabricMCPTool: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: FabricValue
    public let annotations: FabricMetadata

    public init(
        name: String,
        description: String,
        inputSchema: FabricValue,
        annotations: FabricMetadata
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
    }
}

public struct FabricMCPContent: Codable, Sendable, Equatable {
    public let type: String
    public let text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct FabricMCPToolCallResponse: Codable, Sendable, Equatable {
    public let content: [FabricMCPContent]
    public let structuredContent: FabricMetadata

    public init(content: [FabricMCPContent], structuredContent: FabricMetadata) {
        self.content = content
        self.structuredContent = structuredContent
    }
}

public struct FabricGateway: Sendable {
    public let broker: FabricBroker
    public let protocolVersion: String
    public let serverInfo: FabricMCPServerInfo

    public init(
        broker: FabricBroker,
        protocolVersion: String = "2026-03-12",
        serverInfo: FabricMCPServerInfo = .init(name: "fabric-gateway", version: "0.1.0")
    ) {
        self.broker = broker
        self.protocolVersion = protocolVersion
        self.serverInfo = serverInfo
    }

    public func initializeResponse() -> FabricMCPInitializeResponse {
        FabricMCPInitializeResponse(
            protocolVersion: protocolVersion,
            capabilities: [
                "resources": .object([:]),
                "tools": .object([:]),
            ],
            serverInfo: serverInfo
        )
    }

    public func listResources(
        callerAppID: String,
        query: String? = nil
    ) async throws -> [FabricMCPResource] {
        let resources = try await broker.discoverResources(callerAppID: callerAppID, query: query)
        return resources.map { descriptor in
            FabricMCPResource(
                uri: descriptor.uri.rawValue,
                name: descriptor.title,
                title: descriptor.title,
                description: descriptor.summary,
                metadata: descriptor.metadata.merging(
                    [
                        "appID": .string(descriptor.uri.appID),
                        "kind": .string(descriptor.kind),
                        "capabilities": .array(descriptor.capabilities.sorted { $0.rawValue < $1.rawValue }.map {
                            .string($0.rawValue)
                        }),
                    ],
                    uniquingKeysWith: { _, newValue in newValue }
                )
            )
        }
    }

    public func listTools(callerAppID: String) async throws -> [FabricMCPTool] {
        let actions = try await broker.listActions(callerAppID: callerAppID)
        return actions.map { action in
            FabricMCPTool(
                name: action.id,
                description: action.summary,
                inputSchema: action.inputSchema,
                annotations: [
                    "appID": .string(action.appID),
                    "title": .string(action.title),
                    "isMutation": .bool(action.isMutation),
                    "requiresConfirmation": .bool(action.requiresConfirmation),
                ]
            )
        }
    }

    public func callTool(
        callerAppID: String,
        name: String,
        arguments: FabricMetadata = [:],
        confirmationToken: String? = nil
    ) async throws -> FabricMCPToolCallResponse {
        let result = try await broker.invokeAction(
            callerAppID: callerAppID,
            invocation: FabricActionInvocation(
                actionID: name,
                arguments: arguments,
                confirmationToken: confirmationToken
            )
        )

        var structuredContent = result.output
        structuredContent["success"] = .bool(result.success)
        structuredContent["message"] = .string(result.message)
        structuredContent["createdResources"] = .array(result.createdResources.map { .string($0.rawValue) })
        structuredContent["updatedResources"] = .array(result.updatedResources.map { .string($0.rawValue) })

        return FabricMCPToolCallResponse(
            content: [
                FabricMCPContent(type: "text", text: result.message)
            ],
            structuredContent: structuredContent
        )
    }
}
