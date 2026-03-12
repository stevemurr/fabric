import Foundation

public enum FabricResourceCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case read
    case mention
    case subscribe
    case open
    case snapshot
}

public struct FabricPresentationHints: Codable, Sendable, Equatable, Hashable {
    public let systemImage: String?
    public let tint: String?
    public let subtitle: String?
    public let categoryLabel: String?

    public init(
        systemImage: String? = nil,
        tint: String? = nil,
        subtitle: String? = nil,
        categoryLabel: String? = nil
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.subtitle = subtitle
        self.categoryLabel = categoryLabel
    }
}

public struct FabricResourceDescriptor: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let uri: FabricURI
    public let kind: String
    public let title: String
    public let summary: String
    public let capabilities: Set<FabricResourceCapability>
    public let metadata: FabricMetadata
    public let presentation: FabricPresentationHints?

    public init(
        uri: FabricURI,
        kind: String,
        title: String,
        summary: String,
        capabilities: Set<FabricResourceCapability>,
        metadata: FabricMetadata = [:],
        presentation: FabricPresentationHints? = nil
    ) {
        self.uri = uri
        self.kind = kind
        self.title = title
        self.summary = summary
        self.capabilities = capabilities
        self.metadata = metadata
        self.presentation = presentation
    }

    public var id: String { uri.rawValue }
}

public struct FabricContextPayload: Codable, Sendable, Equatable {
    public let uri: FabricURI
    public let kind: String
    public let title: String
    public let body: String
    public let metadata: FabricMetadata
    public let presentation: FabricPresentationHints?

    public init(
        uri: FabricURI,
        kind: String,
        title: String,
        body: String,
        metadata: FabricMetadata = [:],
        presentation: FabricPresentationHints? = nil
    ) {
        self.uri = uri
        self.kind = kind
        self.title = title
        self.body = body
        self.metadata = metadata
        self.presentation = presentation
    }
}

public struct FabricActionDescriptor: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let appID: String
    public let name: String
    public let title: String
    public let summary: String
    public let inputSchema: FabricValue
    public let isMutation: Bool
    public let requiresConfirmation: Bool

    public init(
        id: String,
        appID: String,
        name: String,
        title: String,
        summary: String,
        inputSchema: FabricValue = .object([:]),
        isMutation: Bool,
        requiresConfirmation: Bool
    ) {
        self.id = id
        self.appID = appID
        self.name = name
        self.title = title
        self.summary = summary
        self.inputSchema = inputSchema
        self.isMutation = isMutation
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct FabricActionInvocation: Codable, Sendable, Equatable {
    public let actionID: String
    public let arguments: FabricMetadata
    public let targetResourceURI: FabricURI?
    public let confirmationToken: String?

    public init(
        actionID: String,
        arguments: FabricMetadata = [:],
        targetResourceURI: FabricURI? = nil,
        confirmationToken: String? = nil
    ) {
        self.actionID = actionID
        self.arguments = arguments
        self.targetResourceURI = targetResourceURI
        self.confirmationToken = confirmationToken
    }
}

public struct FabricActionResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let message: String
    public let output: FabricMetadata
    public let createdResources: [FabricURI]
    public let updatedResources: [FabricURI]

    public init(
        success: Bool,
        message: String,
        output: FabricMetadata = [:],
        createdResources: [FabricURI] = [],
        updatedResources: [FabricURI] = []
    ) {
        self.success = success
        self.message = message
        self.output = output
        self.createdResources = createdResources
        self.updatedResources = updatedResources
    }
}
