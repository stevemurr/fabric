import Foundation

public enum FabricError: Error, LocalizedError, Sendable, Equatable {
    case invalidURI(String)
    case duplicateProvider(String)
    case appNotRegistered(String)
    case resourceNotFound(String)
    case actionNotFound(String)
    case permissionDenied(String)
    case confirmationRequired(String)
    case invalidConfirmationToken(String)
    case unsupportedSubscription(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let value):
            return "Invalid Fabric URI: \(value)"
        case .duplicateProvider(let appID):
            return "Provider already registered for app '\(appID)'"
        case .appNotRegistered(let appID):
            return "No Fabric providers registered for app '\(appID)'"
        case .resourceNotFound(let uri):
            return "Fabric resource not found: \(uri)"
        case .actionNotFound(let actionID):
            return "Fabric action not found: \(actionID)"
        case .permissionDenied(let message):
            return "Fabric permission denied: \(message)"
        case .confirmationRequired(let actionID):
            return "Fabric confirmation required for action '\(actionID)'"
        case .invalidConfirmationToken(let token):
            return "Fabric confirmation token is invalid or expired: \(token)"
        case .unsupportedSubscription(let description):
            return "Fabric subscription is not supported: \(description)"
        }
    }
}
