import Foundation

public protocol FabricResourceProvider: Sendable {
    var appID: String { get }
    func listResources(query: String?) async throws -> [FabricResourceDescriptor]
    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload?
}

public protocol FabricActionProvider: Sendable {
    var appID: String { get }
    func listActions() async throws -> [FabricActionDescriptor]
    func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult
}

public protocol FabricSubscriptionProvider: Sendable {
    var appID: String { get }
    func validateSubscription(_ request: FabricSubscriptionRequest) async throws
}

public struct AnyFabricResourceProvider: Sendable {
    public let appID: String
    private let listResourcesHandler: @Sendable (String?) async throws -> [FabricResourceDescriptor]
    private let resolveContextHandler: @Sendable (FabricURI) async throws -> FabricContextPayload?

    public init<P: FabricResourceProvider>(_ provider: P) {
        self.appID = provider.appID
        self.listResourcesHandler = provider.listResources
        self.resolveContextHandler = provider.resolveContext
    }

    public init(
        appID: String,
        listResources: @escaping @Sendable (String?) async throws -> [FabricResourceDescriptor],
        resolveContext: @escaping @Sendable (FabricURI) async throws -> FabricContextPayload?
    ) {
        self.appID = appID
        self.listResourcesHandler = listResources
        self.resolveContextHandler = resolveContext
    }

    public func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        try await listResourcesHandler(query)
    }

    public func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        try await resolveContextHandler(uri)
    }
}

public struct AnyFabricActionProvider: Sendable {
    public let appID: String
    private let listActionsHandler: @Sendable () async throws -> [FabricActionDescriptor]
    private let invokeHandler: @Sendable (FabricActionInvocation) async throws -> FabricActionResult

    public init<P: FabricActionProvider>(_ provider: P) {
        self.appID = provider.appID
        self.listActionsHandler = provider.listActions
        self.invokeHandler = provider.invoke
    }

    public init(
        appID: String,
        listActions: @escaping @Sendable () async throws -> [FabricActionDescriptor],
        invoke: @escaping @Sendable (FabricActionInvocation) async throws -> FabricActionResult
    ) {
        self.appID = appID
        self.listActionsHandler = listActions
        self.invokeHandler = invoke
    }

    public func listActions() async throws -> [FabricActionDescriptor] {
        try await listActionsHandler()
    }

    public func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        try await invokeHandler(invocation)
    }
}

public struct AnyFabricSubscriptionProvider: Sendable {
    public let appID: String
    private let validateHandler: @Sendable (FabricSubscriptionRequest) async throws -> Void

    public init<P: FabricSubscriptionProvider>(_ provider: P) {
        self.appID = provider.appID
        self.validateHandler = provider.validateSubscription
    }

    public init(
        appID: String,
        validateSubscription: @escaping @Sendable (FabricSubscriptionRequest) async throws -> Void
    ) {
        self.appID = appID
        self.validateHandler = validateSubscription
    }

    public func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        try await validateHandler(request)
    }
}

public struct FabricAppRegistration: Sendable {
    public let appID: String
    public let resourceProvider: AnyFabricResourceProvider?
    public let actionProvider: AnyFabricActionProvider?
    public let subscriptionProvider: AnyFabricSubscriptionProvider?

    public init(
        appID: String,
        resourceProvider: AnyFabricResourceProvider? = nil,
        actionProvider: AnyFabricActionProvider? = nil,
        subscriptionProvider: AnyFabricSubscriptionProvider? = nil
    ) {
        self.appID = appID
        self.resourceProvider = resourceProvider
        self.actionProvider = actionProvider
        self.subscriptionProvider = subscriptionProvider
    }
}
