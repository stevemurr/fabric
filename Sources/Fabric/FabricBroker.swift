import Foundation

private struct FabricSubscriber: Sendable {
    let id: UUID
    let callerAppID: String
    let request: FabricSubscriptionRequest
    let continuation: AsyncStream<FabricEvent>.Continuation
}

public actor FabricBroker {
    public let permissionStore: FabricPermissionStore

    private var resourceProviders: [String: AnyFabricResourceProvider] = [:]
    private var actionProviders: [String: AnyFabricActionProvider] = [:]
    private var subscriptionProviders: [String: AnyFabricSubscriptionProvider] = [:]
    private var subscribers: [UUID: FabricSubscriber] = [:]

    public init(permissionStore: FabricPermissionStore = FabricPermissionStore()) {
        self.permissionStore = permissionStore
    }

    public func register(_ registration: FabricAppRegistration) throws {
        if let resourceProvider = registration.resourceProvider {
            try registerResourceProvider(resourceProvider, expectedAppID: registration.appID)
        }

        if let actionProvider = registration.actionProvider {
            try registerActionProvider(actionProvider, expectedAppID: registration.appID)
        }

        if let subscriptionProvider = registration.subscriptionProvider {
            try registerSubscriptionProvider(subscriptionProvider, expectedAppID: registration.appID)
        }
    }

    public func unregisterApp(_ appID: String) {
        resourceProviders[appID] = nil
        actionProviders[appID] = nil
        subscriptionProviders[appID] = nil

        let subscriberIDs = subscribers.values
            .filter { $0.request.appID == appID || $0.callerAppID == appID }
            .map(\.id)

        for subscriberID in subscriberIDs {
            removeSubscriber(id: subscriberID)
        }
    }

    public func registerResourceProvider(_ provider: AnyFabricResourceProvider) throws {
        try registerResourceProvider(provider, expectedAppID: provider.appID)
    }

    public func registerActionProvider(_ provider: AnyFabricActionProvider) throws {
        try registerActionProvider(provider, expectedAppID: provider.appID)
    }

    public func registerSubscriptionProvider(_ provider: AnyFabricSubscriptionProvider) throws {
        try registerSubscriptionProvider(provider, expectedAppID: provider.appID)
    }

    private func registerResourceProvider(
        _ provider: AnyFabricResourceProvider,
        expectedAppID: String
    ) throws {
        guard provider.appID == expectedAppID else {
            throw FabricError.appNotRegistered(expectedAppID)
        }

        guard resourceProviders[provider.appID] == nil else {
            throw FabricError.duplicateProvider(provider.appID)
        }

        resourceProviders[provider.appID] = provider
    }

    private func registerActionProvider(
        _ provider: AnyFabricActionProvider,
        expectedAppID: String
    ) throws {
        guard provider.appID == expectedAppID else {
            throw FabricError.appNotRegistered(expectedAppID)
        }

        guard actionProviders[provider.appID] == nil else {
            throw FabricError.duplicateProvider(provider.appID)
        }

        actionProviders[provider.appID] = provider
    }

    private func registerSubscriptionProvider(
        _ provider: AnyFabricSubscriptionProvider,
        expectedAppID: String
    ) throws {
        guard provider.appID == expectedAppID else {
            throw FabricError.appNotRegistered(expectedAppID)
        }

        guard subscriptionProviders[provider.appID] == nil else {
            throw FabricError.duplicateProvider(provider.appID)
        }

        subscriptionProviders[provider.appID] = provider
    }

    public func grant(_ permission: FabricPermissionGrant) async {
        await permissionStore.grant(permission)
    }

    public func revoke(_ permission: FabricPermissionGrant) async {
        await permissionStore.revoke(permission)
    }

    public func issueConfirmationToken(
        callerAppID: String,
        calleeAppID: String,
        actionID: String,
        ttl: TimeInterval = 300
    ) async -> String {
        await permissionStore.issueConfirmationToken(
            callerAppID: callerAppID,
            calleeAppID: calleeAppID,
            actionID: actionID,
            ttl: ttl
        )
    }

    public func discoverResources(
        callerAppID: String,
        query: String? = nil
    ) async throws -> [FabricResourceDescriptor] {
        var resources: [FabricResourceDescriptor] = []

        for (appID, provider) in resourceProviders.sorted(by: { $0.key < $1.key }) {
            let hasGrant = await permissionStore.hasGrant(
                callerAppID: callerAppID,
                calleeAppID: appID,
                capability: .discoverResources
            )

            guard hasGrant else { continue }

            resources.append(contentsOf: try await provider.listResources(query: query))
        }

        return resources.sorted { lhs, rhs in
            if lhs.uri.appID != rhs.uri.appID {
                return lhs.uri.appID < rhs.uri.appID
            }
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public func listActions(callerAppID: String) async throws -> [FabricActionDescriptor] {
        var actions: [FabricActionDescriptor] = []

        for (appID, provider) in actionProviders.sorted(by: { $0.key < $1.key }) {
            let providerActions = try await provider.listActions()

            for action in providerActions {
                let hasGrant = await permissionStore.hasGrant(
                    callerAppID: callerAppID,
                    calleeAppID: appID,
                    capability: .invokeAction(action.id)
                )

                if hasGrant {
                    actions.append(action)
                }
            }
        }

        return actions.sorted { $0.id < $1.id }
    }

    public func resolveContexts(
        callerAppID: String,
        uris: [FabricURI]
    ) async throws -> [FabricContextPayload] {
        var contexts: [FabricContextPayload] = []

        for uri in uris {
            guard let provider = resourceProviders[uri.appID] else {
                throw FabricError.resourceNotFound(uri.rawValue)
            }

            let hasGrant = await permissionStore.hasGrant(
                callerAppID: callerAppID,
                calleeAppID: uri.appID,
                capability: .readContext
            )

            guard hasGrant else {
                throw FabricError.permissionDenied(
                    "\(callerAppID) cannot read resources from \(uri.appID)"
                )
            }

            guard let context = try await provider.resolveContext(for: uri) else {
                throw FabricError.resourceNotFound(uri.rawValue)
            }

            contexts.append(context)
        }

        return contexts
    }

    public func invokeAction(
        callerAppID: String,
        invocation: FabricActionInvocation
    ) async throws -> FabricActionResult {
        let located = try await locateAction(invocation.actionID)
        let action = located.action
        let provider = located.provider

        let hasGrant = await permissionStore.hasGrant(
            callerAppID: callerAppID,
            calleeAppID: action.appID,
            capability: .invokeAction(action.id)
        )

        guard hasGrant else {
            throw FabricError.permissionDenied(
                "\(callerAppID) cannot invoke \(action.id) on \(action.appID)"
            )
        }

        if action.isMutation && action.requiresConfirmation {
            guard await permissionStore.consumeConfirmationToken(
                invocation.confirmationToken,
                callerAppID: callerAppID,
                calleeAppID: action.appID,
                actionID: action.id
            ) else {
                if invocation.confirmationToken == nil {
                    throw FabricError.confirmationRequired(action.id)
                }
                throw FabricError.invalidConfirmationToken(invocation.confirmationToken ?? "")
            }
        }

        let result = try await provider.invoke(invocation)
        await publish(
            FabricEvent(
                appID: action.appID,
                kind: .actionCompleted,
                payload: [
                    "actionID": .string(action.id),
                    "success": .bool(result.success),
                    "message": .string(result.message),
                ]
            )
        )
        return result
    }

    public func subscribe(
        callerAppID: String,
        request: FabricSubscriptionRequest
    ) async throws -> FabricSubscription {
        let targetProviders: [String: AnyFabricSubscriptionProvider]

        if let appID = request.appID {
            guard let provider = subscriptionProviders[appID] else {
                throw FabricError.unsupportedSubscription("No subscription provider for \(appID)")
            }
            targetProviders = [appID: provider]
        } else {
            targetProviders = subscriptionProviders
        }

        var validatedAny = false

        for (appID, provider) in targetProviders {
            let hasGrant = await permissionStore.hasGrant(
                callerAppID: callerAppID,
                calleeAppID: appID,
                capability: .subscribeResources
            )

            guard hasGrant else { continue }
            try await provider.validateSubscription(request)
            validatedAny = true
        }

        guard validatedAny else {
            throw FabricError.permissionDenied(
                "\(callerAppID) cannot subscribe to the requested Fabric events"
            )
        }

        let id = UUID()
        let stream = AsyncStream<FabricEvent> { continuation in
            subscribers[id] = FabricSubscriber(
                id: id,
                callerAppID: callerAppID,
                request: request,
                continuation: continuation
            )
            continuation.onTermination = { _ in
                Task {
                    await self.removeSubscriber(id: id)
                }
            }
        }

        return FabricSubscription(
            id: id,
            stream: stream,
            cancelHandler: { [weak self] in
                await self?.removeSubscriber(id: id)
            }
        )
    }

    public func publish(_ event: FabricEvent) async {
        for subscriber in subscribers.values where subscriber.request.matches(event) {
            subscriber.continuation.yield(event)
        }
    }

    private func removeSubscriber(id: UUID) {
        guard let subscriber = subscribers.removeValue(forKey: id) else { return }
        subscriber.continuation.finish()
    }

    private func locateAction(
        _ actionID: String
    ) async throws -> (action: FabricActionDescriptor, provider: AnyFabricActionProvider) {
        for provider in actionProviders.values {
            let actions = try await provider.listActions()
            if let action = actions.first(where: { $0.id == actionID }) {
                return (action, provider)
            }
        }

        throw FabricError.actionNotFound(actionID)
    }
}
