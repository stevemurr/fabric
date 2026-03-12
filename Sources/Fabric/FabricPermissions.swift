import Foundation

public struct FabricCapability: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let discoverResources = FabricCapability(rawValue: "resource.discover")
    public static let readContext = FabricCapability(rawValue: "resource.read")
    public static let subscribeResources = FabricCapability(rawValue: "resource.subscribe")

    public static func invokeAction(_ actionID: String) -> FabricCapability {
        FabricCapability(rawValue: "action.invoke.\(actionID)")
    }
}

public struct FabricPermissionGrant: Codable, Hashable, Sendable {
    public let callerAppID: String
    public let calleeAppID: String
    public let capability: FabricCapability

    public init(callerAppID: String, calleeAppID: String, capability: FabricCapability) {
        self.callerAppID = callerAppID
        self.calleeAppID = calleeAppID
        self.capability = capability
    }
}

private struct FabricConfirmationRecord: Sendable {
    let token: String
    let callerAppID: String
    let calleeAppID: String
    let actionID: String
    let expiresAt: Date
}

public actor FabricPermissionStore {
    private var grants: Set<FabricPermissionGrant> = []
    private var confirmations: [String: FabricConfirmationRecord] = [:]

    public init() {}

    public func grant(_ permission: FabricPermissionGrant) {
        grants.insert(permission)
    }

    public func revoke(_ permission: FabricPermissionGrant) {
        grants.remove(permission)
    }

    public func hasGrant(
        callerAppID: String,
        calleeAppID: String,
        capability: FabricCapability
    ) -> Bool {
        grants.contains(
            FabricPermissionGrant(
                callerAppID: callerAppID,
                calleeAppID: calleeAppID,
                capability: capability
            )
        )
    }

    public func issueConfirmationToken(
        callerAppID: String,
        calleeAppID: String,
        actionID: String,
        ttl: TimeInterval = 300
    ) -> String {
        let token = UUID().uuidString
        confirmations[token] = FabricConfirmationRecord(
            token: token,
            callerAppID: callerAppID,
            calleeAppID: calleeAppID,
            actionID: actionID,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        return token
    }

    public func consumeConfirmationToken(
        _ token: String?,
        callerAppID: String,
        calleeAppID: String,
        actionID: String
    ) -> Bool {
        guard let token, let record = confirmations[token] else {
            return false
        }

        guard record.expiresAt >= Date(),
              record.callerAppID == callerAppID,
              record.calleeAppID == calleeAppID,
              record.actionID == actionID else {
            confirmations[token] = nil
            return false
        }

        confirmations[token] = nil
        return true
    }
}
