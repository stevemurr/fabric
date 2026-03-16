import Foundation
import XCTest
@testable import Fabric
@testable import FabricGateway

private actor RemoteShowcaseNotesApp: FabricResourceProvider, FabricActionProvider {
    nonisolated let appID = "showcase.notes"
    private var notes: [String: Note]

    init() {
        self.notes = [
            "note-1": Note(
                id: "note-1",
                title: "Welcome to Fabric",
                body: "This note is exposed over the XPC-backed showcase."
            )
        ]
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        notes.values.sorted { $0.title < $1.title }.map { note in
            FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "note", id: note.id),
                kind: "note",
                title: note.title,
                summary: note.body,
                capabilities: [.read, .mention, .open]
            )
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        guard uri.kind == "note", let note = notes[uri.id] else {
            return nil
        }

        return FabricContextPayload(
            uri: uri,
            kind: uri.kind,
            title: note.title,
            body: note.body
        )
    }

    func listActions() async throws -> [FabricActionDescriptor] {
        [
            FabricActionDescriptor(
                id: "showcase.notes.create-note",
                appID: appID,
                name: "create-note",
                title: "Create Note",
                summary: "Create a note in the showcase notebook.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": "string",
                        "body": "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            )
        ]
    }

    func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        guard invocation.actionID == "showcase.notes.create-note" else {
            throw FabricError.actionNotFound(invocation.actionID)
        }

        let title = invocation.arguments["title"]?.stringValue ?? "Untitled Note"
        let body = invocation.arguments["body"]?.stringValue ?? ""
        let id = UUID().uuidString
        notes[id] = Note(id: id, title: title, body: body)

        let uri = FabricURI(appID: appID, kind: "note", id: id)
        return FabricActionResult(
            success: true,
            message: "Created note '\(title)'",
            output: [
                "noteURI": .string(uri.rawValue),
                "title": .string(title),
            ],
            createdResources: [uri]
        )
    }

    private struct Note: Sendable {
        let id: String
        let title: String
        let body: String
    }
}

private struct AnonymousXPCFixture {
    let service: FabricXPCService
    let providerClient: FabricXPCClient
    let consumerClient: FabricXPCClient
}

private func makeAnonymousXPCFixture() async throws -> AnonymousXPCFixture {
    let listener = NSXPCListener.anonymous()
    let service = FabricXPCService(listener: listener)
    listener.resume()

    let provider = RemoteShowcaseNotesApp()
    let providerClient = FabricXPCClient(
        connection: NSXPCConnection(listenerEndpoint: listener.endpoint),
        resourceProvider: AnyFabricResourceProvider(provider),
        actionProvider: AnyFabricActionProvider(provider)
    )
    try await providerClient.register(
        appID: "showcase.notes",
        exposesResources: true,
        exposesActions: true,
        exposesSubscriptions: false
    )

    let consumerClient = FabricXPCClient(connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
    return AnonymousXPCFixture(
        service: service,
        providerClient: providerClient,
        consumerClient: consumerClient
    )
}

final class FabricXPCGatewayTests: XCTestCase {
    func testXPCClientIssuesConfirmationTokenForSharedBrokerMutation() async throws {
        let fixture = try await makeAnonymousXPCFixture()

        let token = try await fixture.consumerClient.issueConfirmationToken(
            callerAppID: "showcase.chat",
            calleeAppID: "showcase.notes",
            actionID: "showcase.notes.create-note"
        )

        let result = try await fixture.consumerClient.invokeAction(
            callerAppID: "showcase.chat",
            invocation: FabricActionInvocation(
                actionID: "showcase.notes.create-note",
                arguments: [
                    "title": .string("XPC Note"),
                    "body": .string("Created through an anonymous XPC listener."),
                ],
                confirmationToken: token
            )
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "Created note 'XPC Note'")
        XCTAssertEqual(result.createdResources.count, 1)
    }

    func testClientBackedGatewayProjectsAndInvokesTools() async throws {
        let fixture = try await makeAnonymousXPCFixture()
        let gateway = FabricXPCGateway(client: fixture.consumerClient)

        let initialize = gateway.initializeResponse()
        let resources = try await gateway.listResources(callerAppID: "showcase.chat")
        let tools = try await gateway.listTools(callerAppID: "showcase.chat")
        let token = try await fixture.consumerClient.issueConfirmationToken(
            callerAppID: "showcase.chat",
            calleeAppID: "showcase.notes",
            actionID: "showcase.notes.create-note"
        )
        let result = try await gateway.callTool(
            callerAppID: "showcase.chat",
            name: "showcase.notes.create-note",
            arguments: [
                "title": .string("Gateway Note"),
                "body": .string("Created through FabricXPCGateway"),
            ],
            confirmationToken: token
        )

        XCTAssertEqual(initialize.serverInfo.name, "fabric-xpc-gateway")
        XCTAssertTrue(resources.contains(where: { $0.uri == "fabric://showcase.notes/note/note-1" }))
        XCTAssertTrue(tools.contains(where: { $0.name == "showcase.notes.create-note" }))
        XCTAssertEqual(result.content.first?.text, "Created note 'Gateway Note'")
        XCTAssertEqual(result.structuredContent["success"]?.boolValue, true)
    }
}
