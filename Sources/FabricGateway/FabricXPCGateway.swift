import Foundation
import Fabric

public struct FabricXPCGateway: Sendable {
    public let client: FabricXPCClient
    public let protocolVersion: String
    public let serverInfo: FabricMCPServerInfo

    public init(
        client: FabricXPCClient,
        protocolVersion: String = "2026-03-12",
        serverInfo: FabricMCPServerInfo = .init(name: "fabric-xpc-gateway", version: "0.1.0")
    ) {
        self.client = client
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
        let resources = try await client.discoverResources(callerAppID: callerAppID, query: query)
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
        let actions = try await client.listActions(callerAppID: callerAppID)
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
        let result = try await client.invokeAction(
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
