import XCTest
@testable import Fabric

final class FabricLaunchAgentTests: XCTestCase {
    func testLaunchAgentRendersMachServicePlist() throws {
        let configuration = FabricLaunchAgentConfiguration(
            executablePath: "/tmp/FabricBrokerRuntime"
        )

        let data = try configuration.renderedPropertyList()
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, "com.stevemurr.fabric.broker")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/tmp/FabricBrokerRuntime", "--mach-service", "com.stevemurr.fabric.broker"]
        )
        XCTAssertEqual(
            (plist["MachServices"] as? [String: Bool])?["com.stevemurr.fabric.broker"],
            true
        )
    }
}
