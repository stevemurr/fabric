import XCTest
@testable import Fabric
@testable import FabricGateway

final class FabricGatewayTests: XCTestCase {
    func testGatewayProjectsResourcesAndTools() async throws {
        let fixture = try await makeFixture()
        let gateway = FabricGateway(broker: fixture.broker)

        await grantReadSuiteAccess(broker: fixture.broker)
        await grantNotesActionAccess(broker: fixture.broker)

        let initialize = gateway.initializeResponse()
        let resources = try await gateway.listResources(callerAppID: "chat")
        let tools = try await gateway.listTools(callerAppID: "chat")

        XCTAssertEqual(initialize.serverInfo.name, "fabric-gateway")
        XCTAssertTrue(resources.contains(where: { $0.uri == "fabric://wheel/tab/tab-1" }))
        XCTAssertTrue(tools.contains(where: { $0.name == "notes.create-note" }))
    }

    func testGatewayCallsToolsThroughBroker() async throws {
        let fixture = try await makeFixture()
        let gateway = FabricGateway(broker: fixture.broker)

        await grantReadSuiteAccess(broker: fixture.broker)
        await grantNotesActionAccess(broker: fixture.broker)

        let token = await fixture.broker.issueConfirmationToken(
            callerAppID: "chat",
            calleeAppID: "notes",
            actionID: "notes.create-note"
        )

        let result = try await gateway.callTool(
            callerAppID: "chat",
            name: "notes.create-note",
            arguments: [
                "title": "Gateway Note",
                "body": "Created through MCP projection",
            ],
            confirmationToken: token
        )

        XCTAssertEqual(result.content.first?.text, "Created note 'Gateway Note'")
        XCTAssertEqual(result.structuredContent["success"]?.boolValue, true)
    }
}
