import Foundation
import Dispatch
import Fabric
import FabricGateway

struct FabricBrokerRuntimeService {
    let broker: FabricBroker
    let gateway: FabricGateway

    func start() {
        let info = gateway.initializeResponse()
        print("Fabric broker runtime started: \(info.serverInfo.name) \(info.serverInfo.version)")
        dispatchMain()
    }
}

@main
struct FabricBrokerRuntimeMain {
    static func main() throws {
        let broker = FabricBroker()
        let gateway = FabricGateway(broker: broker)

        if CommandLine.arguments.contains("--describe") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(gateway.initializeResponse())
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let service = FabricBrokerRuntimeService(
            broker: broker,
            gateway: gateway
        )
        service.start()
    }
}
