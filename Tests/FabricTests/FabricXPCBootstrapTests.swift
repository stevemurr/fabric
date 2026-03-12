import XCTest
@testable import Fabric

final class FabricXPCBootstrapTests: XCTestCase {
    func testBootstrapGrantsChatReadAndInvokeAccessForFirstPartyApps() {
        let action = FabricActionDescriptor(
            id: "wheel.notes.create-note",
            appID: "wheel.notes",
            name: "create-note",
            title: "Create Note",
            summary: "Create a note",
            isMutation: true,
            requiresConfirmation: true
        )

        let grants = fabricFirstPartyBootstrapGrants(
            for: "wheel.notes",
            actions: [action]
        )

        XCTAssertEqual(
            Set(grants),
            [
                FabricPermissionGrant(
                    callerAppID: "wheel.chat",
                    calleeAppID: "wheel.notes",
                    capability: .discoverResources
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.chat",
                    calleeAppID: "wheel.notes",
                    capability: .readContext
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.chat",
                    calleeAppID: "wheel.notes",
                    capability: .subscribeResources
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.chat",
                    calleeAppID: "wheel.notes",
                    capability: .invokeAction("wheel.notes.create-note")
                ),
            ]
        )
    }

    func testBootstrapSkipsAppsWithoutSuitePrefix() {
        XCTAssertTrue(
            fabricFirstPartyBootstrapGrants(
                for: "notes",
                actions: []
            )
            .isEmpty
        )
    }
}
