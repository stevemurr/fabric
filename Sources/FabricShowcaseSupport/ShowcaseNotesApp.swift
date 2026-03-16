import Foundation
import Fabric

public actor ShowcaseNotesApp: FabricResourceProvider, FabricActionProvider, FabricSubscriptionProvider {
    public nonisolated let appID = ShowcaseAppIDs.notes

    private var notes: [ShowcaseNote]
    private var currentPage: FabricContextPayload?
    private var currentSelection: FabricContextPayload?
    private var statusLine: String?
    private var fabric: FabricXPCClient?
    private let onSnapshot: ShowcaseNotesSnapshotHandler

    public init(
        notes: [ShowcaseNote] = ShowcaseSeedData.notes,
        onSnapshot: @escaping ShowcaseNotesSnapshotHandler = { _ in }
    ) {
        self.notes = notes
        self.onSnapshot = onSnapshot
    }

    public func attach(client: FabricXPCClient) async {
        self.fabric = client
        await publishSnapshot()
    }

    public func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        let resources = notes.map { note in
            FabricResourceDescriptor(
                uri: ShowcaseURIs.note(note.id),
                kind: ShowcaseResourceKinds.note,
                title: note.title,
                summary: note.body,
                capabilities: [.read, .mention, .subscribe, .open],
                metadata: showcaseMetadata(for: note.source)
            )
        }

        guard let query, !query.isEmpty else { return resources }
        return resources.filter { resource in
            [
                resource.title,
                resource.summary,
                resource.metadata[ShowcaseMetadataKeys.sourceURL]?.stringValue ?? "",
                resource.metadata[ShowcaseMetadataKeys.sourceURI]?.stringValue ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query.lowercased())
        }
    }

    public func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        guard uri.kind == ShowcaseResourceKinds.note,
              let note = notes.first(where: { $0.id == uri.id }) else {
            return nil
        }

        return FabricContextPayload(
            uri: ShowcaseURIs.note(note.id),
            kind: ShowcaseResourceKinds.note,
            title: note.title,
            body: note.body,
            metadata: showcaseMetadata(for: note.source)
        )
    }

    public func listActions() async throws -> [FabricActionDescriptor] {
        [
            FabricActionDescriptor(
                id: ShowcaseActionIDs.createNote,
                appID: appID,
                name: "create-note",
                title: "Create Note",
                summary: "Create a new note in the showcase notebook.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": "string",
                        "body": "string",
                        ShowcaseMetadataKeys.sourceURI: "string",
                        ShowcaseMetadataKeys.sourceURL: "string",
                        ShowcaseMetadataKeys.capturedSelection: "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            ),
            FabricActionDescriptor(
                id: ShowcaseActionIDs.appendToNote,
                appID: appID,
                name: "append-to-note",
                title: "Append To Note",
                summary: "Append content to an existing showcase note.",
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
                id: ShowcaseActionIDs.openNote,
                appID: appID,
                name: "open-note",
                title: "Open Note",
                summary: "Resolve a showcase note as an explicit action result.",
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

    public func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        switch invocation.actionID {
        case ShowcaseActionIDs.createNote:
            let title = invocation.arguments["title"]?.stringValue ?? "Untitled Note"
            let body = invocation.arguments["body"]?.stringValue ?? ""
            let note = ShowcaseNote(
                id: UUID().uuidString,
                title: title,
                body: body,
                source: source(from: invocation.arguments)
            )
            notes.append(note)
            statusLine = "Created note '\(note.title)'"
            await publishSnapshot()
            try await publishNoteEvent(kind: .resourceUpdated, note: note)

            let uri = ShowcaseURIs.note(note.id)
            return FabricActionResult(
                success: true,
                message: "Created note '\(note.title)'",
                output: noteOutput(for: note, uri: uri),
                createdResources: [uri]
            )

        case ShowcaseActionIDs.appendToNote:
            guard let noteURIString = invocation.arguments["noteURI"]?.stringValue else {
                throw FabricError.invalidURI("missing noteURI")
            }
            let noteURI = try FabricURI(string: noteURIString)
            guard let content = invocation.arguments["content"]?.stringValue,
                  let index = notes.firstIndex(where: { $0.id == noteURI.id }) else {
                throw FabricError.resourceNotFound(noteURIString)
            }

            if notes[index].body.isEmpty {
                notes[index].body = content
            } else {
                notes[index].body += "\n\n" + content
            }

            statusLine = "Updated note '\(notes[index].title)'"
            await publishSnapshot()
            try await publishNoteEvent(kind: .resourceUpdated, note: notes[index])

            return FabricActionResult(
                success: true,
                message: "Updated note '\(notes[index].title)'",
                output: noteOutput(for: notes[index], uri: noteURI),
                updatedResources: [noteURI]
            )

        case ShowcaseActionIDs.openNote:
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
                output: noteOutput(for: note, uri: noteURI)
            )

        default:
            throw FabricError.actionNotFound(invocation.actionID)
        }
    }

    public func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let appID = request.appID, appID != self.appID {
            throw FabricError.unsupportedSubscription(
                "showcase.notes cannot validate subscription for \(appID)"
            )
        }
    }

    public func refreshLiveContext(
        page: FabricContextPayload?,
        selection: FabricContextPayload?
    ) async {
        currentPage = page
        currentSelection = selection
        await publishSnapshot()
    }

    public func updateStatusLine(_ value: String?) async {
        statusLine = value
        await publishSnapshot()
    }

    private func source(from arguments: FabricMetadata) -> ShowcaseNoteSource? {
        showcaseSource(from: arguments)
    }

    private func noteOutput(for note: ShowcaseNote, uri: FabricURI) -> FabricMetadata {
        var output: FabricMetadata = [
            "noteURI": .string(uri.rawValue),
            "title": .string(note.title),
            "body": .string(note.body),
        ]

        for (key, value) in showcaseMetadata(for: note.source) {
            output[key] = value
        }

        return output
    }

    private func publishNoteEvent(kind: FabricEventKind, note: ShowcaseNote) async throws {
        guard let fabric else { return }
        let uri = ShowcaseURIs.note(note.id)

        var payload: FabricMetadata = [
            "noteURI": .string(uri.rawValue),
            "title": .string(note.title),
        ]
        for (key, value) in showcaseMetadata(for: note.source) {
            payload[key] = value
        }

        try await fabric.publish(
            event: FabricEvent(
                appID: appID,
                kind: kind,
                resourceURI: uri,
                resourceKind: ShowcaseResourceKinds.note,
                payload: payload
            ),
            from: appID
        )
    }

    private func publishSnapshot() async {
        await onSnapshot(
            ShowcaseNotesSnapshot(
                notes: notes,
                currentPage: currentPage,
                currentSelection: currentSelection,
                statusLine: statusLine
            )
        )
    }
}
