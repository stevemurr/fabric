import Foundation

public enum FabricError: Error, LocalizedError, Sendable, Equatable, Codable {
    case invalidURI(String)
    case duplicateProvider(String)
    case appNotRegistered(String)
    case resourceNotFound(String)
    case actionNotFound(String)
    case permissionDenied(String)
    case confirmationRequired(String)
    case invalidConfirmationToken(String)
    case unsupportedSubscription(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
    }

    private enum Kind: String, Codable {
        case invalidURI
        case duplicateProvider
        case appNotRegistered
        case resourceNotFound
        case actionNotFound
        case permissionDenied
        case confirmationRequired
        case invalidConfirmationToken
        case unsupportedSubscription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let message = try container.decode(String.self, forKey: .message)

        switch kind {
        case .invalidURI:
            self = .invalidURI(message)
        case .duplicateProvider:
            self = .duplicateProvider(message)
        case .appNotRegistered:
            self = .appNotRegistered(message)
        case .resourceNotFound:
            self = .resourceNotFound(message)
        case .actionNotFound:
            self = .actionNotFound(message)
        case .permissionDenied:
            self = .permissionDenied(message)
        case .confirmationRequired:
            self = .confirmationRequired(message)
        case .invalidConfirmationToken:
            self = .invalidConfirmationToken(message)
        case .unsupportedSubscription:
            self = .unsupportedSubscription(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .invalidURI(let message):
            try container.encode(Kind.invalidURI, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .duplicateProvider(let message):
            try container.encode(Kind.duplicateProvider, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .appNotRegistered(let message):
            try container.encode(Kind.appNotRegistered, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .resourceNotFound(let message):
            try container.encode(Kind.resourceNotFound, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .actionNotFound(let message):
            try container.encode(Kind.actionNotFound, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .permissionDenied(let message):
            try container.encode(Kind.permissionDenied, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .confirmationRequired(let message):
            try container.encode(Kind.confirmationRequired, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .invalidConfirmationToken(let message):
            try container.encode(Kind.invalidConfirmationToken, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .unsupportedSubscription(let message):
            try container.encode(Kind.unsupportedSubscription, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }

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
