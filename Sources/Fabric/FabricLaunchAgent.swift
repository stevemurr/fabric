import Foundation

public enum FabricXPCConstants {
    public static let machServiceName = "com.stevemurr.fabric.broker"
    public static let launchAgentLabel = "com.stevemurr.fabric.broker"
}

public struct FabricLaunchAgentConfiguration: Sendable, Equatable {
    public let label: String
    public let machServiceName: String
    public let executablePath: String
    public let standardOutPath: String?
    public let standardErrorPath: String?

    public init(
        label: String = FabricXPCConstants.launchAgentLabel,
        machServiceName: String = FabricXPCConstants.machServiceName,
        executablePath: String,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil
    ) {
        self.label = label
        self.machServiceName = machServiceName
        self.executablePath = executablePath
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }

    public func propertyList() -> [String: Any] {
        var propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "--mach-service", machServiceName],
            "MachServices": [machServiceName: true],
            "RunAtLoad": true,
            "KeepAlive": true,
        ]

        if let standardOutPath {
            propertyList["StandardOutPath"] = standardOutPath
        }

        if let standardErrorPath {
            propertyList["StandardErrorPath"] = standardErrorPath
        }

        return propertyList
    }

    public func renderedPropertyList() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: propertyList(),
            format: .xml,
            options: 0
        )
    }
}
