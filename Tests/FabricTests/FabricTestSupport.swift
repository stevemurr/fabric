import Foundation
import XCTest
@testable import Fabric

struct BrowserTab: Sendable {
    let id: String
    var title: String
    var url: String
    var body: String
    var selectedText: String?
}

struct NoteRecord: Sendable {
    let id: String
    var title: String
    var body: String
}

actor InMemoryBrowserApp: FabricResourceProvider, FabricSubscriptionProvider {
    nonisolated let appID = "wheel"

    private var tabs: [BrowserTab]
    private var currentTabID: String
    private let broker: FabricBroker

    init(broker: FabricBroker) {
        self.broker = broker
        self.tabs = [
            BrowserTab(
                id: "tab-1",
                title: "Fabric Architecture",
                url: "https://example.com/fabric",
                body: "Fabric is a local inter-app substrate for context and actions.",
                selectedText: "local inter-app substrate"
            ),
            BrowserTab(
                id: "tab-2",
                title: "MCP Notes",
                url: "https://example.com/mcp",
                body: "MCP is useful as a model-facing adapter, not the core transport.",
                selectedText: nil
            ),
        ]
        self.currentTabID = "tab-1"
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        let resources = resourceCatalog()
        guard let query, !query.isEmpty else { return resources }

        return resources.filter { resource in
            let haystack = [
                resource.title,
                resource.summary,
                resource.metadata["url"]?.stringValue ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(query.lowercased())
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        switch uri.kind {
        case "page":
            guard let tab = currentTab else { return nil }
            return FabricContextPayload(
                uri: uri,
                kind: uri.kind,
                title: tab.title,
                body: tab.body,
                metadata: [
                    "url": .string(tab.url),
                    "source": .string("current-page"),
                ]
            )

        case "selection":
            guard let tab = currentTab, let selectedText = tab.selectedText else { return nil }
            return FabricContextPayload(
                uri: uri,
                kind: uri.kind,
                title: "Selection from \(tab.title)",
                body: selectedText,
                metadata: [
                    "url": .string(tab.url),
                    "source": .string("selection"),
                ]
            )

        case "tab":
            guard let tab = tabs.first(where: { $0.id == uri.id }) else { return nil }
            return FabricContextPayload(
                uri: uri,
                kind: uri.kind,
                title: tab.title,
                body: tab.body,
                metadata: [
                    "url": .string(tab.url),
                    "source": .string("tab"),
                ]
            )

        default:
            return nil
        }
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let appID = request.appID, appID != self.appID {
            throw FabricError.unsupportedSubscription("wheel cannot validate subscription for \(appID)")
        }
    }

    func currentTabResources() async throws -> [FabricResourceDescriptor] {
        try await listResources(query: nil).filter { $0.kind == "tab" }
    }

    func setCurrentTab(id: String) async {
        guard tabs.contains(where: { $0.id == id }) else { return }
        currentTabID = id

        let uri = FabricURI(appID: appID, kind: "page", id: "current")
        await broker.publish(
            FabricEvent(
                appID: appID,
                kind: .currentPageChanged,
                resourceURI: uri,
                resourceKind: "page",
                payload: [
                    "tabID": .string(id),
                ]
            )
        )
    }

    private var currentTab: BrowserTab? {
        tabs.first(where: { $0.id == currentTabID })
    }

    private func resourceCatalog() -> [FabricResourceDescriptor] {
        var resources: [FabricResourceDescriptor] = tabs.map { tab in
            FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "tab", id: tab.id),
                kind: "tab",
                title: tab.title,
                summary: tab.url,
                capabilities: [.read, .mention],
                metadata: [
                    "url": .string(tab.url),
                ]
            )
        }

        if let currentTab {
            resources.insert(
                FabricResourceDescriptor(
                    uri: FabricURI(appID: appID, kind: "page", id: "current"),
                    kind: "page",
                    title: "Current Page",
                    summary: currentTab.title,
                    capabilities: [.read, .mention, .subscribe],
                    metadata: [
                        "url": .string(currentTab.url),
                    ]
                ),
                at: 0
            )

            if let selectedText = currentTab.selectedText, !selectedText.isEmpty {
                resources.insert(
                    FabricResourceDescriptor(
                        uri: FabricURI(appID: appID, kind: "selection", id: currentTab.id),
                        kind: "selection",
                        title: "Current Selection",
                        summary: selectedText,
                        capabilities: [.read, .mention, .subscribe],
                        metadata: [
                            "url": .string(currentTab.url),
                        ]
                    ),
                    at: 1
                )
            }
        }

        return resources
    }
}

actor InMemoryNotesApp: FabricResourceProvider, FabricActionProvider, FabricSubscriptionProvider {
    nonisolated let appID = "notes"

    private var notes: [NoteRecord]
    private let broker: FabricBroker

    init(broker: FabricBroker) {
        self.broker = broker
        self.notes = [
            NoteRecord(
                id: "note-1",
                title: "Existing System Notes",
                body: "The first version should broker context and actions."
            )
        ]
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        let resources = notes.map { note in
            FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "note", id: note.id),
                kind: "note",
                title: note.title,
                summary: note.body,
                capabilities: [.read, .mention, .subscribe, .open],
                metadata: [:]
            )
        }

        guard let query, !query.isEmpty else { return resources }
        return resources.filter { resource in
            [resource.title, resource.summary]
                .joined(separator: " ")
                .lowercased()
                .contains(query.lowercased())
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        guard uri.kind == "note",
              let note = notes.first(where: { $0.id == uri.id }) else {
            return nil
        }

        return FabricContextPayload(
            uri: uri,
            kind: uri.kind,
            title: note.title,
            body: note.body,
            metadata: [:]
        )
    }

    func listActions() async throws -> [FabricActionDescriptor] {
        [
            FabricActionDescriptor(
                id: "notes.create-note",
                appID: appID,
                name: "create-note",
                title: "Create Note",
                summary: "Create a new note in the notes app.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": "string",
                        "body": "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            ),
            FabricActionDescriptor(
                id: "notes.append-to-note",
                appID: appID,
                name: "append-to-note",
                title: "Append To Note",
                summary: "Append content to an existing note.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "noteURI": "string",
                        "content": "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            ),
            FabricActionDescriptor(
                id: "notes.open-note",
                appID: appID,
                name: "open-note",
                title: "Open Note",
                summary: "Resolve a note as an explicit action result.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "noteURI": "string",
                    ],
                ],
                isMutation: false,
                requiresConfirmation: false
            ),
        ]
    }

    func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        switch invocation.actionID {
        case "notes.create-note":
            let title = invocation.arguments["title"]?.stringValue ?? "Untitled Note"
            let body = invocation.arguments["body"]?.stringValue ?? ""
            let note = NoteRecord(id: UUID().uuidString, title: title, body: body)
            notes.append(note)

            let uri = FabricURI(appID: appID, kind: "note", id: note.id)
            await broker.publish(
                FabricEvent(
                    appID: appID,
                    kind: .resourceUpdated,
                    resourceURI: uri,
                    resourceKind: "note",
                    payload: [
                        "title": .string(title),
                    ]
                )
            )

            return FabricActionResult(
                success: true,
                message: "Created note '\(title)'",
                output: [
                    "noteURI": .string(uri.rawValue),
                    "title": .string(title),
                ],
                createdResources: [uri]
            )

        case "notes.append-to-note":
            guard let noteURIString = invocation.arguments["noteURI"]?.stringValue else {
                throw FabricError.invalidURI("missing noteURI")
            }
            let noteURI = try FabricURI(string: noteURIString)
            guard let content = invocation.arguments["content"]?.stringValue,
                  let index = notes.firstIndex(where: { $0.id == noteURI.id }) else {
                throw FabricError.resourceNotFound(noteURIString)
            }

            notes[index].body += "\n" + content
            await broker.publish(
                FabricEvent(
                    appID: appID,
                    kind: .resourceUpdated,
                    resourceURI: noteURI,
                    resourceKind: "note",
                    payload: [
                        "title": .string(notes[index].title),
                    ]
                )
            )

            return FabricActionResult(
                success: true,
                message: "Updated note '\(notes[index].title)'",
                output: [
                    "noteURI": .string(noteURI.rawValue),
                    "title": .string(notes[index].title),
                ],
                updatedResources: [noteURI]
            )

        case "notes.open-note":
            guard let noteURIString = invocation.arguments["noteURI"]?.stringValue else {
                throw FabricError.invalidURI("missing noteURI")
            }
            let noteURI = try FabricURI(string: noteURIString)
            guard let note = notes.first(where: { $0.id == noteURI.id }) else {
                throw FabricError.resourceNotFound(noteURIString)
            }

            return FabricActionResult(
                success: true,
                message: "Opened note '\(note.title)'",
                output: [
                    "noteURI": .string(noteURI.rawValue),
                    "title": .string(note.title),
                    "body": .string(note.body),
                ]
            )

        default:
            throw FabricError.actionNotFound(invocation.actionID)
        }
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let appID = request.appID, appID != self.appID {
            throw FabricError.unsupportedSubscription("notes cannot validate subscription for \(appID)")
        }
    }
}

struct FabricFixture {
    let broker: FabricBroker
    let browser: InMemoryBrowserApp
    let notes: InMemoryNotesApp
    let resolver: FabricContextResolver
}

func makeFixture() async throws -> FabricFixture {
    let broker = FabricBroker()
    let browser = InMemoryBrowserApp(broker: broker)
    let notes = InMemoryNotesApp(broker: broker)

    try await broker.register(
        FabricAppRegistration(
            appID: browser.appID,
            resourceProvider: AnyFabricResourceProvider(browser),
            subscriptionProvider: AnyFabricSubscriptionProvider(browser)
        )
    )
    try await broker.register(
        FabricAppRegistration(
            appID: notes.appID,
            resourceProvider: AnyFabricResourceProvider(notes),
            actionProvider: AnyFabricActionProvider(notes),
            subscriptionProvider: AnyFabricSubscriptionProvider(notes)
        )
    )

    return FabricFixture(
        broker: broker,
        browser: browser,
        notes: notes,
        resolver: FabricContextResolver(broker: broker)
    )
}

func grantReadSuiteAccess(broker: FabricBroker, callerAppID: String = "chat") async {
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "wheel",
            capability: .discoverResources
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "wheel",
            capability: .readContext
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "wheel",
            capability: .subscribeResources
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .discoverResources
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .readContext
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .subscribeResources
        )
    )
}

func grantNotesActionAccess(broker: FabricBroker, callerAppID: String = "chat") async {
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .invokeAction("notes.create-note")
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .invokeAction("notes.append-to-note")
        )
    )
    await broker.grant(
        FabricPermissionGrant(
            callerAppID: callerAppID,
            calleeAppID: "notes",
            capability: .invokeAction("notes.open-note")
        )
    )
}

enum TimeoutError: Error {
    case elapsed
}

func firstEvent(
    from stream: AsyncStream<FabricEvent>,
    trigger: @escaping @Sendable () async -> Void
) async throws -> FabricEvent {
    try await withThrowingTaskGroup(of: FabricEvent.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let event = await iterator.next() else {
                throw TimeoutError.elapsed
            }
            return event
        }

        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw TimeoutError.elapsed
        }

        await trigger()

        guard let value = try await group.next() else {
            throw TimeoutError.elapsed
        }

        group.cancelAll()
        return value
    }
}
