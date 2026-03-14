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

    func testBootstrapGrantsMutualResourceAccessToRegisteredSiblingApps() {
        let grants = fabricFirstPartyBootstrapGrants(
            for: "wheel.notes",
            actions: [],
            existingAppIDs: ["wheel.browser", "wheel.chat", "external.docs", "wheel.notes"]
        )

        XCTAssertTrue(
            Set([
                FabricPermissionGrant(
                    callerAppID: "wheel.notes",
                    calleeAppID: "wheel.browser",
                    capability: .discoverResources
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.notes",
                    calleeAppID: "wheel.browser",
                    capability: .readContext
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.notes",
                    calleeAppID: "wheel.browser",
                    capability: .subscribeResources
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.browser",
                    calleeAppID: "wheel.notes",
                    capability: .discoverResources
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.browser",
                    calleeAppID: "wheel.notes",
                    capability: .readContext
                ),
                FabricPermissionGrant(
                    callerAppID: "wheel.browser",
                    calleeAppID: "wheel.notes",
                    capability: .subscribeResources
                ),
            ])
            .isSubset(of: Set(grants))
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
