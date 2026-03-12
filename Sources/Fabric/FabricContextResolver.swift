import Foundation

public struct FabricContextResolver: Sendable {
    public let broker: FabricBroker

    public init(broker: FabricBroker) {
        self.broker = broker
    }

    public func resolve(
        callerAppID: String,
        uris: [FabricURI]
    ) async throws -> [FabricContextPayload] {
        try await broker.resolveContexts(callerAppID: callerAppID, uris: uris)
    }
}
