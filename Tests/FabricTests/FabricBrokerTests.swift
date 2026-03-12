import XCTest
@testable import Fabric

final class FabricBrokerTests: XCTestCase {
    func testDiscoveryFiltersResourcesByGrantedApps() async throws {
        let fixture = try await makeFixture()

        await fixture.broker.grant(
            FabricPermissionGrant(
                callerAppID: "chat",
                calleeAppID: "wheel",
                capability: .discoverResources
            )
        )

        let resources = try await fixture.broker.discoverResources(callerAppID: "chat")

        XCTAssertFalse(resources.isEmpty)
        XCTAssertTrue(resources.allSatisfy { $0.uri.appID == "wheel" })
    }

    func testDuplicateProviderRegistrationIsRejected() async throws {
        let broker = FabricBroker()
        let browser = InMemoryBrowserApp(broker: broker)

        try await broker.registerResourceProvider(AnyFabricResourceProvider(browser))

        do {
            try await broker.registerResourceProvider(AnyFabricResourceProvider(browser))
            XCTFail("Expected duplicate provider registration to throw")
        } catch let error as FabricError {
            XCTAssertEqual(error, .duplicateProvider("wheel"))
        }
    }
}
