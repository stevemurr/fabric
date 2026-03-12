import Foundation

enum FabricCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

enum FabricXPCErrorBridge {
    static let domain = "FabricXPC"
    static let serializedErrorKey = "fabric.serialized-error"

    static func asNSError(_ error: Error) -> NSError {
        if let fabricError = error as? FabricError,
           let data = try? FabricCodec.encode(fabricError) {
            return NSError(
                domain: domain,
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: fabricError.localizedDescription,
                    serializedErrorKey: data,
                ]
            )
        }

        let nsError = error as NSError
        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: nsError.userInfo.merging(
                [NSLocalizedDescriptionKey: nsError.localizedDescription],
                uniquingKeysWith: { current, _ in current }
            )
        )
    }

    static func asError(_ error: Error?) -> Error {
        guard let error else {
            return FabricError.permissionDenied("Unknown Fabric XPC error")
        }

        let nsError = error as NSError
        if nsError.domain == domain,
           let data = nsError.userInfo[serializedErrorKey] as? Data,
           let fabricError = try? FabricCodec.decode(FabricError.self, from: data) {
            return fabricError
        }

        return error
    }
}
