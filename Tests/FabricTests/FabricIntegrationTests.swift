import XCTest
@testable import Fabric

final class FabricIntegrationTests: XCTestCase {
    func testCrossAppDiscoveryResolutionAndStoreTabsInNewNote() async throws {
        let fixture = try await makeFixture()
        await grantReadSuiteAccess(broker: fixture.broker)
        await grantNotesActionAccess(broker: fixture.broker)

        let mentionables = try await fixture.broker.discoverResources(callerAppID: "chat")
        let browserTabs = mentionables.filter { $0.uri.appID == "wheel" && $0.kind == "tab" }
        let existingNotes = mentionables.filter { $0.uri.appID == "notes" && $0.kind == "note" }

        XCTAssertEqual(browserTabs.count, 2)
        XCTAssertEqual(existingNotes.count, 1)

        let tabContexts = try await fixture.resolver.resolve(
            callerAppID: "chat",
            uris: browserTabs.map(\.uri)
        )

        let noteCreateToken = await fixture.broker.issueConfirmationToken(
            callerAppID: "chat",
            calleeAppID: "notes",
            actionID: "notes.create-note"
        )

        let createResult = try await fixture.broker.invokeAction(
            callerAppID: "chat",
            invocation: FabricActionInvocation(
                actionID: "notes.create-note",
                arguments: [
                    "title": "Tab Dump",
                    "body": "Collected from Fabric",
                ],
                confirmationToken: noteCreateToken
            )
        )

        guard let createdNoteURIString = createResult.output["noteURI"]?.stringValue else {
            return XCTFail("Expected created note URI")
        }

        let appendToken = await fixture.broker.issueConfirmationToken(
            callerAppID: "chat",
            calleeAppID: "notes",
            actionID: "notes.append-to-note"
        )

        let appendedContent = tabContexts
            .map { "\($0.title)\n\($0.body)" }
            .joined(separator: "\n\n")

        let appendResult = try await fixture.broker.invokeAction(
            callerAppID: "chat",
            invocation: FabricActionInvocation(
                actionID: "notes.append-to-note",
                arguments: [
                    "noteURI": .string(createdNoteURIString),
                    "content": .string(appendedContent),
                ],
                confirmationToken: appendToken
            )
        )

        XCTAssertTrue(appendResult.success)
        XCTAssertEqual(appendResult.updatedResources.count, 1)

        let noteContext = try await fixture.resolver.resolve(
            callerAppID: "chat",
            uris: [try FabricURI(string: createdNoteURIString)]
        )

        XCTAssertEqual(noteContext.count, 1)
        XCTAssertTrue(noteContext[0].body.contains("Fabric Architecture"))
        XCTAssertTrue(noteContext[0].body.contains("MCP Notes"))
    }
}
