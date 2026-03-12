import Foundation

public struct FabricXPCRegistrationRequest: Codable, Sendable, Equatable {
    public let appID: String
    public let exposesResources: Bool
    public let exposesActions: Bool
    public let exposesSubscriptions: Bool

    public init(
        appID: String,
        exposesResources: Bool,
        exposesActions: Bool,
        exposesSubscriptions: Bool
    ) {
        self.appID = appID
        self.exposesResources = exposesResources
        self.exposesActions = exposesActions
        self.exposesSubscriptions = exposesSubscriptions
    }
}

extension NSXPCConnection: @retroactive @unchecked Sendable {}

private final class FabricDataReplyBox: @unchecked Sendable {
    private let reply: (Data?, NSError?) -> Void

    init(_ reply: @escaping (Data?, NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data?, _ error: NSError?) {
        reply(data, error)
    }
}

private final class FabricErrorReplyBox: @unchecked Sendable {
    private let reply: (NSError?) -> Void

    init(_ reply: @escaping (NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ error: NSError?) {
        reply(error)
    }
}

private final class FabricStringReplyBox: @unchecked Sendable {
    private let reply: (String?, NSError?) -> Void

    init(_ reply: @escaping (String?, NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ value: String?, _ error: NSError?) {
        reply(value, error)
    }
}

@objc public protocol FabricXPCBrokerProtocol {
    func registerApp(_ registrationData: Data, reply: @escaping (NSError?) -> Void)
    func unregisterApp(_ appID: String, reply: @escaping (NSError?) -> Void)
    func discoverResources(_ callerAppID: String, query: String?, reply: @escaping (Data?, NSError?) -> Void)
    func listActions(_ callerAppID: String, reply: @escaping (Data?, NSError?) -> Void)
    func resolveContexts(_ callerAppID: String, uriData: Data, reply: @escaping (Data?, NSError?) -> Void)
    func invokeAction(_ callerAppID: String, invocationData: Data, reply: @escaping (Data?, NSError?) -> Void)
    func subscribe(_ callerAppID: String, requestData: Data, reply: @escaping (String?, NSError?) -> Void)
    func cancelSubscription(_ subscriptionID: String, reply: @escaping (NSError?) -> Void)
    func publishEvent(_ appID: String, eventData: Data, reply: @escaping (NSError?) -> Void)
}

@objc public protocol FabricXPCClientProtocol {
    func listResources(_ query: String?, reply: @escaping (Data?, NSError?) -> Void)
    func resolveContext(_ uri: String, reply: @escaping (Data?, NSError?) -> Void)
    func listActions(_ reply: @escaping (Data?, NSError?) -> Void)
    func invokeAction(_ invocationData: Data, reply: @escaping (Data?, NSError?) -> Void)
    func validateSubscription(_ requestData: Data, reply: @escaping (NSError?) -> Void)
    func didReceiveEvent(_ subscriptionID: String, eventData: Data)
}

public final class FabricXPCRemoteResourceProvider: @unchecked Sendable, FabricResourceProvider {
    public let appID: String
    private let connection: NSXPCConnection

    public init(appID: String, connection: NSXPCConnection) {
        self.appID = appID
        self.connection = connection
    }

    public func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        try await withCheckedThrowingContinuation { continuation in
            remoteProxy().listResources(query) { data, error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    return
                }

                do {
                    let resources = try FabricCodec.decode([FabricResourceDescriptor].self, from: data ?? Data())
                    continuation.resume(returning: resources)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        try await withCheckedThrowingContinuation { continuation in
            remoteProxy().resolveContext(uri.rawValue) { data, error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    return
                }

                guard let data, !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let payload = try FabricCodec.decode(FabricContextPayload.self, from: data)
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func remoteProxy() -> FabricXPCClientProtocol {
        connection.remoteObjectProxyWithErrorHandler { _ in } as! FabricXPCClientProtocol
    }
}

public final class FabricXPCRemoteActionProvider: @unchecked Sendable, FabricActionProvider {
    public let appID: String
    private let connection: NSXPCConnection

    public init(appID: String, connection: NSXPCConnection) {
        self.appID = appID
        self.connection = connection
    }

    public func listActions() async throws -> [FabricActionDescriptor] {
        try await withCheckedThrowingContinuation { continuation in
            remoteProxy().listActions { data, error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    return
                }

                do {
                    let actions = try FabricCodec.decode([FabricActionDescriptor].self, from: data ?? Data())
                    continuation.resume(returning: actions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try FabricCodec.encode(invocation)
                remoteProxy().invokeAction(data) { resultData, error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                        return
                    }

                    do {
                        let result = try FabricCodec.decode(FabricActionResult.self, from: resultData ?? Data())
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func remoteProxy() -> FabricXPCClientProtocol {
        connection.remoteObjectProxyWithErrorHandler { _ in } as! FabricXPCClientProtocol
    }
}

public final class FabricXPCRemoteSubscriptionProvider: @unchecked Sendable, FabricSubscriptionProvider {
    public let appID: String
    private let connection: NSXPCConnection

    public init(appID: String, connection: NSXPCConnection) {
        self.appID = appID
        self.connection = connection
    }

    public func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let data = try FabricCodec.encode(request)
                remoteProxy().validateSubscription(data) { error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func remoteProxy() -> FabricXPCClientProtocol {
        connection.remoteObjectProxyWithErrorHandler { _ in } as! FabricXPCClientProtocol
    }
}

actor FabricXPCSubscriptionStore {
    private var continuations: [String: AsyncStream<FabricEvent>.Continuation] = [:]

    func makeSubscription(
        id: String,
        cancelHandler: @escaping @Sendable () async throws -> Void
    ) -> FabricSubscription {
        let stream = AsyncStream<FabricEvent> { continuation in
            continuations[id] = continuation
            continuation.onTermination = { _ in
                Task {
                    await self.remove(id: id)
                    try? await cancelHandler()
                }
            }
        }

        return FabricSubscription(
            id: UUID(uuidString: id) ?? UUID(),
            stream: stream,
            cancelHandler: {
                await self.remove(id: id)
                try? await cancelHandler()
            }
        )
    }

    func deliver(subscriptionID: String, event: FabricEvent) {
        continuations[subscriptionID]?.yield(event)
    }

    func remove(id: String) {
        let continuation = continuations.removeValue(forKey: id)
        continuation?.finish()
    }
}

final class FabricXPCClientEndpoint: NSObject, FabricXPCClientProtocol {
    private let resourceProvider: AnyFabricResourceProvider?
    private let actionProvider: AnyFabricActionProvider?
    private let subscriptionProvider: AnyFabricSubscriptionProvider?
    private let subscriptionStore: FabricXPCSubscriptionStore

    init(
        resourceProvider: AnyFabricResourceProvider?,
        actionProvider: AnyFabricActionProvider?,
        subscriptionProvider: AnyFabricSubscriptionProvider?,
        subscriptionStore: FabricXPCSubscriptionStore
    ) {
        self.resourceProvider = resourceProvider
        self.actionProvider = actionProvider
        self.subscriptionProvider = subscriptionProvider
        self.subscriptionStore = subscriptionStore
    }

    public func listResources(_ query: String?, reply: @escaping (Data?, NSError?) -> Void) {
        guard let resourceProvider else {
            reply(nil, FabricXPCErrorBridge.asNSError(FabricError.appNotRegistered("No resource provider exported")))
            return
        }

        let replyBox = FabricDataReplyBox(reply)
        Task {
            do {
                replyBox.send(try FabricCodec.encode(try await resourceProvider.listResources(query: query)), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func resolveContext(_ uri: String, reply: @escaping (Data?, NSError?) -> Void) {
        guard let resourceProvider else {
            reply(nil, FabricXPCErrorBridge.asNSError(FabricError.appNotRegistered("No resource provider exported")))
            return
        }

        let replyBox = FabricDataReplyBox(reply)
        Task {
            do {
                let parsedURI = try FabricURI(string: uri)
                let context = try await resourceProvider.resolveContext(for: parsedURI)
                let data = try context.map { try FabricCodec.encode($0) } ?? Data()
                replyBox.send(data, nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func listActions(_ reply: @escaping (Data?, NSError?) -> Void) {
        guard let actionProvider else {
            reply(nil, FabricXPCErrorBridge.asNSError(FabricError.appNotRegistered("No action provider exported")))
            return
        }

        let replyBox = FabricDataReplyBox(reply)
        Task {
            do {
                replyBox.send(try FabricCodec.encode(try await actionProvider.listActions()), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func invokeAction(_ invocationData: Data, reply: @escaping (Data?, NSError?) -> Void) {
        guard let actionProvider else {
            reply(nil, FabricXPCErrorBridge.asNSError(FabricError.appNotRegistered("No action provider exported")))
            return
        }

        let replyBox = FabricDataReplyBox(reply)
        Task {
            do {
                let invocation = try FabricCodec.decode(FabricActionInvocation.self, from: invocationData)
                let result = try await actionProvider.invoke(invocation)
                replyBox.send(try FabricCodec.encode(result), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func validateSubscription(_ requestData: Data, reply: @escaping (NSError?) -> Void) {
        guard let subscriptionProvider else {
            reply(FabricXPCErrorBridge.asNSError(FabricError.unsupportedSubscription("No subscription provider exported")))
            return
        }

        let replyBox = FabricErrorReplyBox(reply)
        Task {
            do {
                let request = try FabricCodec.decode(FabricSubscriptionRequest.self, from: requestData)
                try await subscriptionProvider.validateSubscription(request)
                replyBox.send(nil)
            } catch {
                replyBox.send(FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func didReceiveEvent(_ subscriptionID: String, eventData: Data) {
        let subscriptionStore = subscriptionStore
        Task {
            guard let event = try? FabricCodec.decode(FabricEvent.self, from: eventData) else { return }
            await subscriptionStore.deliver(subscriptionID: subscriptionID, event: event)
        }
    }
}

public final class FabricXPCClient: @unchecked Sendable {
    private let machServiceName: String
    private let connection: NSXPCConnection
    private let subscriptionStore = FabricXPCSubscriptionStore()
    private let endpoint: FabricXPCClientEndpoint

    public init(
        machServiceName: String = FabricXPCConstants.machServiceName,
        resourceProvider: AnyFabricResourceProvider? = nil,
        actionProvider: AnyFabricActionProvider? = nil,
        subscriptionProvider: AnyFabricSubscriptionProvider? = nil
    ) {
        self.machServiceName = machServiceName
        self.connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        self.endpoint = FabricXPCClientEndpoint(
            resourceProvider: resourceProvider,
            actionProvider: actionProvider,
            subscriptionProvider: subscriptionProvider,
            subscriptionStore: subscriptionStore
        )

        connection.remoteObjectInterface = NSXPCInterface(with: FabricXPCBrokerProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: FabricXPCClientProtocol.self)
        connection.exportedObject = endpoint
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    public func register(
        appID: String,
        exposesResources: Bool = true,
        exposesActions: Bool = true,
        exposesSubscriptions: Bool = true
    ) async throws {
        let request = FabricXPCRegistrationRequest(
            appID: appID,
            exposesResources: exposesResources,
            exposesActions: exposesActions,
            exposesSubscriptions: exposesSubscriptions
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let data = try FabricCodec.encode(request)
                brokerProxy().registerApp(data) { error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func unregister(appID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            brokerProxy().unregisterApp(appID) { error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func discoverResources(
        callerAppID: String,
        query: String? = nil
    ) async throws -> [FabricResourceDescriptor] {
        try await withCheckedThrowingContinuation { continuation in
            brokerProxy().discoverResources(callerAppID, query: query) { data, error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    return
                }

                do {
                    let resources = try FabricCodec.decode([FabricResourceDescriptor].self, from: data ?? Data())
                    continuation.resume(returning: resources)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func listActions(callerAppID: String) async throws -> [FabricActionDescriptor] {
        try await withCheckedThrowingContinuation { continuation in
            brokerProxy().listActions(callerAppID) { data, error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    return
                }

                do {
                    let actions = try FabricCodec.decode([FabricActionDescriptor].self, from: data ?? Data())
                    continuation.resume(returning: actions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func resolveContexts(
        callerAppID: String,
        uris: [FabricURI]
    ) async throws -> [FabricContextPayload] {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try FabricCodec.encode(uris)
                brokerProxy().resolveContexts(callerAppID, uriData: data) { contextData, error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                        return
                    }

                    do {
                        let contexts = try FabricCodec.decode([FabricContextPayload].self, from: contextData ?? Data())
                        continuation.resume(returning: contexts)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func invokeAction(
        callerAppID: String,
        invocation: FabricActionInvocation
    ) async throws -> FabricActionResult {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try FabricCodec.encode(invocation)
                brokerProxy().invokeAction(callerAppID, invocationData: data) { resultData, error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                        return
                    }

                    do {
                        let result = try FabricCodec.decode(FabricActionResult.self, from: resultData ?? Data())
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func subscribe(
        callerAppID: String,
        request: FabricSubscriptionRequest
    ) async throws -> FabricSubscription {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let requestData = try FabricCodec.encode(request)
                brokerProxy().subscribe(callerAppID, requestData: requestData) { subscriptionID, error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                        return
                    }

                    guard let subscriptionID else {
                        continuation.resume(throwing: FabricError.unsupportedSubscription("Broker returned no subscription ID"))
                        return
                    }

                    Task {
                        let subscription = await self.subscriptionStore.makeSubscription(
                            id: subscriptionID,
                            cancelHandler: { [weak self] in
                                try await self?.cancelSubscription(id: subscriptionID)
                            }
                        )
                        continuation.resume(returning: subscription)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func publish(event: FabricEvent, from appID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let eventData = try FabricCodec.encode(event)
                brokerProxy().publishEvent(appID, eventData: eventData) { error in
                    if let error {
                        continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancelSubscription(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            brokerProxy().cancelSubscription(id) { error in
                if let error {
                    continuation.resume(throwing: FabricXPCErrorBridge.asError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func brokerProxy() -> FabricXPCBrokerProtocol {
        connection.remoteObjectProxyWithErrorHandler { _ in } as! FabricXPCBrokerProtocol
    }
}

private struct FabricServiceSubscription: Sendable {
    let id: String
    let clientAppID: String
    let connectionID: ObjectIdentifier
    let subscription: FabricSubscription
    let forwardTask: Task<Void, Never>
}

actor FabricXPCServiceCoordinator {
    private let broker: FabricBroker
    private var connectionsByAppID: [String: NSXPCConnection] = [:]
    private var appIDByConnectionID: [ObjectIdentifier: Set<String>] = [:]
    private var subscriptionsByID: [String: FabricServiceSubscription] = [:]
    private var subscriptionIDsByConnectionID: [ObjectIdentifier: Set<String>] = [:]

    init(broker: FabricBroker) {
        self.broker = broker
    }

    func registerApp(
        request: FabricXPCRegistrationRequest,
        connection: NSXPCConnection
    ) async throws {
        let connectionID = ObjectIdentifier(connection)

        let resourceProvider = request.exposesResources
            ? AnyFabricResourceProvider(FabricXPCRemoteResourceProvider(appID: request.appID, connection: connection))
            : nil
        let actionProvider = request.exposesActions
            ? AnyFabricActionProvider(FabricXPCRemoteActionProvider(appID: request.appID, connection: connection))
            : nil
        let subscriptionProvider = request.exposesSubscriptions
            ? AnyFabricSubscriptionProvider(FabricXPCRemoteSubscriptionProvider(appID: request.appID, connection: connection))
            : nil

        try await broker.register(
            FabricAppRegistration(
                appID: request.appID,
                resourceProvider: resourceProvider,
                actionProvider: actionProvider,
                subscriptionProvider: subscriptionProvider
            )
        )

        connectionsByAppID[request.appID] = connection
        appIDByConnectionID[connectionID, default: []].insert(request.appID)
    }

    func unregisterApp(_ appID: String) async {
        await broker.unregisterApp(appID)
        connectionsByAppID[appID] = nil

        for (connectionID, appIDs) in appIDByConnectionID {
            if appIDs.contains(appID) {
                var updated = appIDs
                updated.remove(appID)
                appIDByConnectionID[connectionID] = updated.isEmpty ? nil : updated
            }
        }
    }

    func disconnect(connection: NSXPCConnection) async {
        let connectionID = ObjectIdentifier(connection)
        await disconnect(connectionID: connectionID)
    }

    func disconnect(connectionID: ObjectIdentifier) async {
        if let appIDs = appIDByConnectionID.removeValue(forKey: connectionID) {
            for appID in appIDs {
                await broker.unregisterApp(appID)
                connectionsByAppID[appID] = nil
            }
        }

        if let subscriptionIDs = subscriptionIDsByConnectionID.removeValue(forKey: connectionID) {
            for subscriptionID in subscriptionIDs {
                if let record = subscriptionsByID.removeValue(forKey: subscriptionID) {
                    record.forwardTask.cancel()
                    await record.subscription.cancel()
                }
            }
        }
    }

    func discoverResources(callerAppID: String, query: String?) async throws -> [FabricResourceDescriptor] {
        try await broker.discoverResources(callerAppID: callerAppID, query: query)
    }

    func listActions(callerAppID: String) async throws -> [FabricActionDescriptor] {
        try await broker.listActions(callerAppID: callerAppID)
    }

    func resolveContexts(callerAppID: String, uris: [FabricURI]) async throws -> [FabricContextPayload] {
        try await broker.resolveContexts(callerAppID: callerAppID, uris: uris)
    }

    func invokeAction(
        callerAppID: String,
        invocation: FabricActionInvocation
    ) async throws -> FabricActionResult {
        try await broker.invokeAction(callerAppID: callerAppID, invocation: invocation)
    }

    func publishEvent(appID: String, event: FabricEvent) async {
        guard event.appID == appID else { return }
        await broker.publish(event)
    }

    func subscribe(
        callerAppID: String,
        request: FabricSubscriptionRequest,
        connection: NSXPCConnection
    ) async throws -> String {
        let connectionID = ObjectIdentifier(connection)
        let subscription = try await broker.subscribe(callerAppID: callerAppID, request: request)
        let subscriptionID = subscription.id.uuidString

        let forwardTask = Task { [weak connection] in
            let remote = connection?.remoteObjectProxyWithErrorHandler { _ in } as? FabricXPCClientProtocol
            for await event in subscription.stream {
                guard !Task.isCancelled else { return }
                guard let remote, let data = try? FabricCodec.encode(event) else { continue }
                remote.didReceiveEvent(subscriptionID, eventData: data)
            }
        }

        subscriptionsByID[subscriptionID] = FabricServiceSubscription(
            id: subscriptionID,
            clientAppID: callerAppID,
            connectionID: connectionID,
            subscription: subscription,
            forwardTask: forwardTask
        )
        subscriptionIDsByConnectionID[connectionID, default: []].insert(subscriptionID)

        return subscriptionID
    }

    func cancelSubscription(_ subscriptionID: String) async {
        guard let record = subscriptionsByID.removeValue(forKey: subscriptionID) else { return }
        record.forwardTask.cancel()
        await record.subscription.cancel()

        var ids = subscriptionIDsByConnectionID[record.connectionID] ?? []
        ids.remove(subscriptionID)
        subscriptionIDsByConnectionID[record.connectionID] = ids.isEmpty ? nil : ids
    }
}

public final class FabricXPCService: NSObject, NSXPCListenerDelegate, FabricXPCBrokerProtocol {
    public let listener: NSXPCListener
    public let broker: FabricBroker
    private let coordinator: FabricXPCServiceCoordinator

    public init(
        machServiceName: String = FabricXPCConstants.machServiceName,
        broker: FabricBroker = FabricBroker()
    ) {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        self.broker = broker
        self.coordinator = FabricXPCServiceCoordinator(broker: broker)
        super.init()
        listener.delegate = self
    }

    public func run() {
        listener.resume()
        RunLoop.current.run()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let coordinator = self.coordinator
        let connectionID = ObjectIdentifier(newConnection)
        newConnection.exportedInterface = NSXPCInterface(with: FabricXPCBrokerProtocol.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: FabricXPCClientProtocol.self)
        newConnection.invalidationHandler = {
            Task {
                await coordinator.disconnect(connectionID: connectionID)
            }
        }
        newConnection.interruptionHandler = {
            Task {
                await coordinator.disconnect(connectionID: connectionID)
            }
        }
        newConnection.resume()
        return true
    }

    public func registerApp(_ registrationData: Data, reply: @escaping (NSError?) -> Void) {
        let replyBox = FabricErrorReplyBox(reply)
        let coordinator = self.coordinator
        guard let connection = NSXPCConnection.current() else {
            replyBox.send(FabricXPCErrorBridge.asNSError(FabricError.appNotRegistered("Missing NSXPC connection context")))
            return
        }

        Task {
            do {
                let request = try FabricCodec.decode(FabricXPCRegistrationRequest.self, from: registrationData)
                try await coordinator.registerApp(request: request, connection: connection)
                replyBox.send(nil)
            } catch {
                replyBox.send(FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func unregisterApp(_ appID: String, reply: @escaping (NSError?) -> Void) {
        let replyBox = FabricErrorReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            await coordinator.unregisterApp(appID)
            replyBox.send(nil)
        }
    }

    public func discoverResources(_ callerAppID: String, query: String?, reply: @escaping (Data?, NSError?) -> Void) {
        let replyBox = FabricDataReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            do {
                let resources = try await coordinator.discoverResources(callerAppID: callerAppID, query: query)
                replyBox.send(try FabricCodec.encode(resources), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func listActions(_ callerAppID: String, reply: @escaping (Data?, NSError?) -> Void) {
        let replyBox = FabricDataReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            do {
                let actions = try await coordinator.listActions(callerAppID: callerAppID)
                replyBox.send(try FabricCodec.encode(actions), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func resolveContexts(_ callerAppID: String, uriData: Data, reply: @escaping (Data?, NSError?) -> Void) {
        let replyBox = FabricDataReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            do {
                let uris = try FabricCodec.decode([FabricURI].self, from: uriData)
                let contexts = try await coordinator.resolveContexts(callerAppID: callerAppID, uris: uris)
                replyBox.send(try FabricCodec.encode(contexts), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func invokeAction(_ callerAppID: String, invocationData: Data, reply: @escaping (Data?, NSError?) -> Void) {
        let replyBox = FabricDataReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            do {
                let invocation = try FabricCodec.decode(FabricActionInvocation.self, from: invocationData)
                let result = try await coordinator.invokeAction(callerAppID: callerAppID, invocation: invocation)
                replyBox.send(try FabricCodec.encode(result), nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func subscribe(_ callerAppID: String, requestData: Data, reply: @escaping (String?, NSError?) -> Void) {
        let replyBox = FabricStringReplyBox(reply)
        let coordinator = self.coordinator
        guard let connection = NSXPCConnection.current() else {
            replyBox.send(nil, FabricXPCErrorBridge.asNSError(FabricError.unsupportedSubscription("Missing NSXPC connection context")))
            return
        }

        Task {
            do {
                let request = try FabricCodec.decode(FabricSubscriptionRequest.self, from: requestData)
                let subscriptionID = try await coordinator.subscribe(
                    callerAppID: callerAppID,
                    request: request,
                    connection: connection
                )
                replyBox.send(subscriptionID, nil)
            } catch {
                replyBox.send(nil, FabricXPCErrorBridge.asNSError(error))
            }
        }
    }

    public func cancelSubscription(_ subscriptionID: String, reply: @escaping (NSError?) -> Void) {
        let replyBox = FabricErrorReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            await coordinator.cancelSubscription(subscriptionID)
            replyBox.send(nil)
        }
    }

    public func publishEvent(_ appID: String, eventData: Data, reply: @escaping (NSError?) -> Void) {
        let replyBox = FabricErrorReplyBox(reply)
        let coordinator = self.coordinator
        Task {
            do {
                let event = try FabricCodec.decode(FabricEvent.self, from: eventData)
                await coordinator.publishEvent(appID: appID, event: event)
                replyBox.send(nil)
            } catch {
                replyBox.send(FabricXPCErrorBridge.asNSError(error))
            }
        }
    }
}
