import Foundation
import Fabric

@main
struct FabricBrokerRuntimeMain {
    static func main() throws {
        let arguments = CommandLine.arguments
        let machServiceName: String = {
            guard let index = arguments.firstIndex(of: "--mach-service"),
                  arguments.indices.contains(index + 1) else {
                return FabricXPCConstants.machServiceName
            }
            return arguments[index + 1]
        }()

        if arguments.contains("--describe") {
            let configuration = FabricLaunchAgentConfiguration(
                machServiceName: machServiceName,
                executablePath: CommandLine.arguments[0]
            )
            let data = try configuration.renderedPropertyList()
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let service = FabricXPCService(machServiceName: machServiceName)
        fputs("Fabric broker runtime listening on mach service \(machServiceName)\n", stderr)
        service.run()
    }
}
