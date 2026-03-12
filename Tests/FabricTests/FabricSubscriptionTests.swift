import XCTest
@testable import Fabric

final class FabricSubscriptionTests: XCTestCase {
    func testSubscribersReceiveCurrentPageEvents() async throws {
        let fixture = try await makeFixture()
        await grantReadSuiteAccess(broker: fixture.broker)

        let subscription = try await fixture.broker.subscribe(
            callerAppID: "chat",
            request: FabricSubscriptionRequest(
                appID: "wheel",
                resourceKind: "page",
                eventKinds: [.currentPageChanged]
            )
        )

        let event = try await firstEvent(from: subscription.stream) {
            await fixture.browser.setCurrentTab(id: "tab-2")
        }

        XCTAssertEqual(event.appID, "wheel")
        XCTAssertEqual(event.kind, .currentPageChanged)
        XCTAssertEqual(event.payload["tabID"]?.stringValue, "tab-2")
    }
}
