import Foundation

public enum FabricEventKind: String, Codable, CaseIterable, Sendable, Hashable {
    case resourceUpdated
    case resourceRemoved
    case currentPageChanged
    case selectionChanged
    case actionCompleted
}

public struct FabricEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let appID: String
    public let kind: FabricEventKind
    public let resourceURI: FabricURI?
    public let resourceKind: String?
    public let payload: FabricMetadata
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        appID: String,
        kind: FabricEventKind,
        resourceURI: FabricURI? = nil,
        resourceKind: String? = nil,
        payload: FabricMetadata = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.appID = appID
        self.kind = kind
        self.resourceURI = resourceURI
        self.resourceKind = resourceKind
        self.payload = payload
        self.timestamp = timestamp
    }
}

public struct FabricSubscriptionRequest: Codable, Sendable, Equatable {
    public let appID: String?
    public let resourceKind: String?
    public let resourceURI: FabricURI?
    public let eventKinds: Set<FabricEventKind>

    public init(
        appID: String? = nil,
        resourceKind: String? = nil,
        resourceURI: FabricURI? = nil,
        eventKinds: Set<FabricEventKind> = Set(FabricEventKind.allCases)
    ) {
        self.appID = appID
        self.resourceKind = resourceKind
        self.resourceURI = resourceURI
        self.eventKinds = eventKinds
    }

    func matches(_ event: FabricEvent) -> Bool {
        if let appID, event.appID != appID {
            return false
        }

        if let resourceKind, event.resourceKind != resourceKind {
            return false
        }

        if let resourceURI, event.resourceURI != resourceURI {
            return false
        }

        return eventKinds.contains(event.kind)
    }
}

public struct FabricSubscription: Sendable {
    public let id: UUID
    public let stream: AsyncStream<FabricEvent>
    private let cancelHandler: @Sendable () async -> Void

    init(
        id: UUID,
        stream: AsyncStream<FabricEvent>,
        cancelHandler: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.stream = stream
        self.cancelHandler = cancelHandler
    }

    public func cancel() async {
        await cancelHandler()
    }
}
