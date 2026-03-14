# Fabric

Fabric is a local macOS substrate for inter-app context sharing. Apps register resource, action, and subscription providers with a broker; other apps can then discover `fabric://...` resources, resolve them into context payloads, invoke actions, and subscribe to updates.

This package currently ships three products:

- `Fabric`: core broker, provider protocols, permission model, subscriptions, and XPC client/service support.
- `FabricGateway`: an MCP-shaped projection over a `FabricBroker`.
- `FabricBrokerRuntime`: a standalone broker runtime you can install as a LaunchAgent-backed Mach service.

## Requirements

- macOS 13+
- Swift 6.2

## Setup

### Clone, build, and test

```bash
git clone git@github.com:stevemurr/fabric.git
cd fabric
swift build
swift test
```

### Add Fabric to your app

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/stevemurr/fabric.git", branch: "main")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Fabric", package: "fabric")
        ]
    )
]
```

Add `FabricGateway` as well if you want the MCP projection layer:

```swift
.product(name: "FabricGateway", package: "fabric")
```

### Install the shared broker runtime

If your apps communicate through XPC, install the broker runtime once per user session:

```bash
./scripts/install-launch-agent.sh
```

That script:

- builds `FabricBrokerRuntime` in release mode
- writes `~/Library/LaunchAgents/com.stevemurr.fabric.broker.plist`
- reloads the LaunchAgent

The default Mach service name is `com.stevemurr.fabric.broker`.

You do not need the LaunchAgent if you embed `FabricBroker` directly in-process.

## Core model

- A resource is described by `FabricResourceDescriptor` and addressed as `fabric://<appID>/<kind>/<id>`.
- A resolved resource becomes a `FabricContextPayload` with a title, body, metadata, and optional presentation hints.
- Actions are described by `FabricActionDescriptor` and invoked with `FabricActionInvocation`.
- Subscriptions stream `FabricEvent` values through `AsyncStream`.
- Access is controlled by `FabricPermissionGrant`.
- Mutating actions can require a one-time confirmation token issued by `FabricBroker.issueConfirmationToken(...)`.

## Integration examples

### 1. Expose resources and actions from an app

This example shows a notes app exposing notes as resources and a read-only `open-note` action:

```swift
import Foundation
import Fabric

struct Note: Sendable {
    let id: String
    var title: String
    var body: String
}

actor NotesApp: FabricResourceProvider, FabricActionProvider, FabricSubscriptionProvider {
    nonisolated let appID = "wheel.notes"
    private var notes: [Note] = [
        .init(id: "welcome", title: "Welcome", body: "Fabric is running.")
    ]

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        notes.map { note in
            FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "note", id: note.id),
                kind: "note",
                title: note.title,
                summary: note.body,
                capabilities: [.read, .mention, .subscribe, .open]
            )
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        guard uri.kind == "note",
              let note = notes.first(where: { $0.id == uri.id }) else {
            return nil
        }

        return FabricContextPayload(
            uri: uri,
            kind: "note",
            title: note.title,
            body: note.body
        )
    }

    func listActions() async throws -> [FabricActionDescriptor] {
        [
            FabricActionDescriptor(
                id: "notes.open-note",
                appID: appID,
                name: "open-note",
                title: "Open Note",
                summary: "Return the full note body.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "noteURI": "string"
                    ]
                ],
                isMutation: false,
                requiresConfirmation: false
            )
        ]
    }

    func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        guard invocation.actionID == "notes.open-note",
              let noteURI = invocation.arguments["noteURI"]?.stringValue else {
            throw FabricError.actionNotFound(invocation.actionID)
        }

        let uri = try FabricURI(string: noteURI)
        guard let note = notes.first(where: { $0.id == uri.id }) else {
            throw FabricError.resourceNotFound(noteURI)
        }

        return FabricActionResult(
            success: true,
            message: "Opened note '\(note.title)'",
            output: [
                "noteURI": .string(uri.rawValue),
                "title": .string(note.title),
                "body": .string(note.body)
            ]
        )
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let appID = request.appID, appID != self.appID {
            throw FabricError.unsupportedSubscription("notes cannot validate \(appID)")
        }
    }
}
```

### 2. Register that app with the shared XPC broker

Keep the `FabricXPCClient` alive for as long as your app should remain registered:

```swift
import Fabric

let notesApp = NotesApp()
let fabric = FabricXPCClient(
    resourceProvider: AnyFabricResourceProvider(notesApp),
    actionProvider: AnyFabricActionProvider(notesApp),
    subscriptionProvider: AnyFabricSubscriptionProvider(notesApp)
)

try await fabric.register(
    appID: notesApp.appID,
    exposesResources: true,
    exposesActions: true,
    exposesSubscriptions: true
)
```

If you use a first-party naming convention like `wheel.notes`, Fabric automatically bootstraps access for `wheel.chat` to discover resources, read context, subscribe, and invoke declared actions. Sibling apps that share the same suite prefix also receive mutual resource discovery/read/subscribe grants.

If you do not use that naming convention, or if you embed `FabricBroker` yourself, grant permissions explicitly.

### 3. Consume resources and actions from another app

A chat app can discover notes, resolve them into context, and invoke a read-only action through the same XPC client type:

```swift
import Fabric

let fabric = FabricXPCClient()

let resources = try await fabric.discoverResources(
    callerAppID: "wheel.chat",
    query: "welcome"
)

if let noteURI = resources.first?.uri {
    let contexts = try await fabric.resolveContexts(
        callerAppID: "wheel.chat",
        uris: [noteURI]
    )

    let result = try await fabric.invokeAction(
        callerAppID: "wheel.chat",
        invocation: FabricActionInvocation(
            actionID: "notes.open-note",
            arguments: [
                "noteURI": .string(noteURI.rawValue)
            ]
        )
    )

    print(contexts.first?.body ?? "")
    print(result.output["body"]?.stringValue ?? "")
}
```

For mutating actions, set `requiresConfirmation` on the descriptor and pass a `confirmationToken` in the invocation. Token issuance currently lives on `FabricBroker`, so that flow is available when you host the broker directly in-process or behind your own gateway/service layer.

### 4. Publish and subscribe to live events

Providers publish events:

```swift
try await fabric.publish(
    event: FabricEvent(
        appID: "wheel.browser",
        kind: .currentPageChanged,
        resourceURI: FabricURI(appID: "wheel.browser", kind: "page", id: "current"),
        resourceKind: "page",
        payload: [
            "tabID": .string("tab-2")
        ]
    ),
    from: "wheel.browser"
)
```

Consumers subscribe with filters:

```swift
let subscription = try await fabric.subscribe(
    callerAppID: "wheel.chat",
    request: FabricSubscriptionRequest(
        appID: "wheel.browser",
        resourceKind: "page",
        eventKinds: [.currentPageChanged]
    )
)

Task {
    for await event in subscription.stream {
        print(event.payload["tabID"]?.stringValue ?? "")
    }
}
```

### 5. Embed the broker directly

If you want everything in one process, skip XPC and register providers directly with `FabricBroker`:

```swift
import Fabric

let broker = FabricBroker()
let notesApp = NotesApp()

try await broker.register(
    FabricAppRegistration(
        appID: notesApp.appID,
        resourceProvider: AnyFabricResourceProvider(notesApp),
        actionProvider: AnyFabricActionProvider(notesApp),
        subscriptionProvider: AnyFabricSubscriptionProvider(notesApp)
    )
)

await broker.grant(
    FabricPermissionGrant(
        callerAppID: "chat",
        calleeAppID: "wheel.notes",
        capability: .discoverResources
    )
)
await broker.grant(
    FabricPermissionGrant(
        callerAppID: "chat",
        calleeAppID: "wheel.notes",
        capability: .readContext
    )
)
await broker.grant(
    FabricPermissionGrant(
        callerAppID: "chat",
        calleeAppID: "wheel.notes",
        capability: .invokeAction("notes.open-note")
    )
)

let resources = try await broker.discoverResources(callerAppID: "chat")
```

For a mutating action your provider exposes, such as `notes.create-note`:

```swift
let token = await broker.issueConfirmationToken(
    callerAppID: "chat",
    calleeAppID: "wheel.notes",
    actionID: "notes.create-note"
)

let result = try await broker.invokeAction(
    callerAppID: "chat",
    invocation: FabricActionInvocation(
        actionID: "notes.create-note",
        arguments: [
            "title": .string("Daily Summary"),
            "body": .string("Collected from Fabric")
        ],
        confirmationToken: token
    )
)
```

### 6. Project Fabric into an MCP-shaped gateway

`FabricGateway` turns broker resources into MCP resources and broker actions into MCP tools. It does not run a transport server by itself; you wrap it in your own stdio, HTTP, or JSON-RPC adapter.

```swift
import Fabric
import FabricGateway

let broker = FabricBroker()
let gateway = FabricGateway(broker: broker)

let initialize = gateway.initializeResponse()
let resources = try await gateway.listResources(callerAppID: "wheel.chat")
let tools = try await gateway.listTools(callerAppID: "wheel.chat")

// Assuming a registered provider exposes notes.create-note.
let token = await broker.issueConfirmationToken(
    callerAppID: "wheel.chat",
    calleeAppID: "wheel.notes",
    actionID: "notes.create-note"
)

let toolResult = try await gateway.callTool(
    callerAppID: "wheel.chat",
    name: "notes.create-note",
    arguments: [
        "title": .string("Gateway Note"),
        "body": .string("Created through FabricGateway")
    ],
    confirmationToken: token
)

print(initialize.serverInfo.name)
print(resources.map(\.uri))
print(tools.map(\.name))
print(toolResult.content.first?.text ?? "")
```

## Notes

- `FabricBrokerRuntime --describe` renders the LaunchAgent plist used by the install script.
- The default LaunchAgent label and Mach service name are both `com.stevemurr.fabric.broker`.
- `FabricGateway` is a projection layer, not a complete MCP server implementation.
