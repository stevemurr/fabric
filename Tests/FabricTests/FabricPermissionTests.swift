import XCTest
@testable import Fabric

final class FabricPermissionTests: XCTestCase {
    func testResolveContextRequiresReadGrant() async throws {
        let fixture = try await makeFixture()

        do {
            _ = try await fixture.resolver.resolve(
                callerAppID: "chat",
                uris: [FabricURI(appID: "wheel", kind: "page", id: "current")]
            )
            XCTFail("Expected read without grant to fail")
        } catch let error as FabricError {
            XCTAssertEqual(
                error,
                .permissionDenied("chat cannot read resources from wheel")
            )
        }
    }

    func testMutationActionRequiresConfirmation() async throws {
        let fixture = try await makeFixture()
        await grantReadSuiteAccess(broker: fixture.broker)
        await grantNotesActionAccess(broker: fixture.broker)

        do {
            _ = try await fixture.broker.invokeAction(
                callerAppID: "chat",
                invocation: FabricActionInvocation(
                    actionID: "notes.create-note",
                    arguments: [
                        "title": "Inbox",
                    ]
                )
            )
            XCTFail("Expected mutation without confirmation to fail")
        } catch let error as FabricError {
            XCTAssertEqual(error, .confirmationRequired("notes.create-note"))
        }
    }

    func testMutationActionAcceptsValidConfirmation() async throws {
        let fixture = try await makeFixture()
        await grantReadSuiteAccess(broker: fixture.broker)
        await grantNotesActionAccess(broker: fixture.broker)

        let token = await fixture.broker.issueConfirmationToken(
            callerAppID: "chat",
            calleeAppID: "notes",
            actionID: "notes.create-note"
        )

        let result = try await fixture.broker.invokeAction(
            callerAppID: "chat",
            invocation: FabricActionInvocation(
                actionID: "notes.create-note",
                arguments: [
                    "title": "Inbox",
                    "body": "Start here",
                ],
                confirmationToken: token
            )
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.createdResources.count, 1)
        XCTAssertEqual(result.output["title"]?.stringValue, "Inbox")
    }
}
