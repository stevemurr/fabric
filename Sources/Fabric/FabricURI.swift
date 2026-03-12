import Foundation

public struct FabricURI: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let appID: String
    public let kind: String
    public let id: String

    public init(appID: String, kind: String, id: String) {
        self.appID = appID
        self.kind = kind
        self.id = id
    }

    public init(rawValue: String) {
        if let parsed = try? Self.parse(rawValue) {
            self = parsed
        } else {
            self = FabricURI(appID: "", kind: "", id: rawValue)
        }
    }

    public init(string: String) throws {
        self = try Self.parse(string)
    }

    public var rawValue: String {
        "fabric://\(appID)/\(kind)/\(id)"
    }

    public var description: String {
        rawValue
    }

    public static func parse(_ value: String) throws -> FabricURI {
        let prefix = "fabric://"
        guard value.hasPrefix(prefix) else {
            throw FabricError.invalidURI(value)
        }

        let remainder = String(value.dropFirst(prefix.count))
        let segments = remainder.split(separator: "/", omittingEmptySubsequences: false)

        guard segments.count >= 3 else {
            throw FabricError.invalidURI(value)
        }

        let appID = String(segments[0])
        let kind = String(segments[1])
        let id = segments.dropFirst(2).map(String.init).joined(separator: "/")

        guard !appID.isEmpty, !kind.isEmpty, !id.isEmpty else {
            throw FabricError.invalidURI(value)
        }

        return FabricURI(
            appID: appID,
            kind: kind,
            id: id
        )
    }
}
