import Foundation
import Fabric

public typealias ShowcaseBrowserSnapshotHandler = @Sendable (ShowcaseBrowserSnapshot) async -> Void
public typealias ShowcaseNotesSnapshotHandler = @Sendable (ShowcaseNotesSnapshot) async -> Void

public struct ShowcaseBrowserTab: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var url: String
    public var body: String
    public var selectedText: String?

    public init(
        id: String,
        title: String,
        url: String,
        body: String,
        selectedText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.body = body
        self.selectedText = selectedText
    }
}

public struct ShowcaseNoteSource: Sendable, Equatable, Hashable {
    public let uri: String
    public let url: String
    public let capturedSelection: String?

    public init(uri: String, url: String, capturedSelection: String? = nil) {
        self.uri = uri
        self.url = url
        self.capturedSelection = capturedSelection
    }
}

public struct ShowcaseNote: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var body: String
    public var source: ShowcaseNoteSource?

    public init(
        id: String,
        title: String,
        body: String,
        source: ShowcaseNoteSource? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
    }
}

public struct ShowcaseNoteLink: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ShowcaseBrowserSnapshot: Sendable, Equatable {
    public let tabs: [ShowcaseBrowserTab]
    public let currentTabID: String
    public let linkedNotesBySourceURI: [String: [ShowcaseNoteLink]]
    public let lastNotebookEvent: String?

    public init(
        tabs: [ShowcaseBrowserTab],
        currentTabID: String,
        linkedNotesBySourceURI: [String: [ShowcaseNoteLink]],
        lastNotebookEvent: String? = nil
    ) {
        self.tabs = tabs
        self.currentTabID = currentTabID
        self.linkedNotesBySourceURI = linkedNotesBySourceURI
        self.lastNotebookEvent = lastNotebookEvent
    }
}

public struct ShowcaseNotesSnapshot: Sendable, Equatable {
    public let notes: [ShowcaseNote]
    public let currentPage: FabricContextPayload?
    public let currentSelection: FabricContextPayload?
    public let statusLine: String?

    public init(
        notes: [ShowcaseNote],
        currentPage: FabricContextPayload?,
        currentSelection: FabricContextPayload?,
        statusLine: String? = nil
    ) {
        self.notes = notes
        self.currentPage = currentPage
        self.currentSelection = currentSelection
        self.statusLine = statusLine
    }
}

public enum ShowcaseSeedData {
    public static let browserTabs: [ShowcaseBrowserTab] = [
        ShowcaseBrowserTab(
            id: "tab-1",
            title: "Fabric as a Local Context Fabric",
            url: "https://example.com/fabric/context-relay",
            body: "Fabric lets local macOS apps expose semantic resources, actions, and live context updates to each other.",
            selectedText: "semantic resources, actions, and live context updates"
        ),
        ShowcaseBrowserTab(
            id: "tab-2",
            title: "Building an Ecosystem of Developer Tools",
            url: "https://example.com/fabric/ecosystem",
            body: "A local broker can make notes, browsers, editors, and agent surfaces feel like one substrate instead of custom point integrations.",
            selectedText: "one substrate instead of custom point integrations"
        ),
        ShowcaseBrowserTab(
            id: "tab-3",
            title: "Why MCP Needs a Real Substrate",
            url: "https://example.com/fabric/mcp",
            body: "MCP works well as a projection layer when the apps already share a common broker for context and actions.",
            selectedText: nil
        ),
    ]

    public static let notes: [ShowcaseNote] = [
        ShowcaseNote(
            id: "note-1",
            title: "Blog Outline",
            body: "Lead with the browser-to-notes story, then reveal the gateway as the same substrate viewed by an agent."
        )
    ]
}

public func showcaseMetadata(for source: ShowcaseNoteSource?) -> FabricMetadata {
    guard let source else { return [:] }

    var metadata: FabricMetadata = [
        ShowcaseMetadataKeys.sourceURI: .string(source.uri),
        ShowcaseMetadataKeys.sourceURL: .string(source.url),
    ]

    if let capturedSelection = source.capturedSelection, !capturedSelection.isEmpty {
        metadata[ShowcaseMetadataKeys.capturedSelection] = .string(capturedSelection)
    }

    return metadata
}

public func showcaseSource(from metadata: FabricMetadata) -> ShowcaseNoteSource? {
    guard let uri = metadata[ShowcaseMetadataKeys.sourceURI]?.stringValue,
          let url = metadata[ShowcaseMetadataKeys.sourceURL]?.stringValue else {
        return nil
    }

    return ShowcaseNoteSource(
        uri: uri,
        url: url,
        capturedSelection: metadata[ShowcaseMetadataKeys.capturedSelection]?.stringValue
    )
}

public func showcaseBacklinks(
    from resources: [FabricResourceDescriptor]
) -> [String: [ShowcaseNoteLink]] {
    var grouped: [String: [ShowcaseNoteLink]] = [:]

    for resource in resources where resource.kind == ShowcaseResourceKinds.note {
        guard let sourceURI = resource.metadata[ShowcaseMetadataKeys.sourceURI]?.stringValue else {
            continue
        }

        grouped[sourceURI, default: []].append(
            ShowcaseNoteLink(id: resource.uri.id, title: resource.title)
        )
    }

    for key in grouped.keys {
        grouped[key] = grouped[key]?.sorted {
            if $0.title != $1.title {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    return grouped
}

public func showcaseNotebookEventMessage(from event: FabricEvent) -> String? {
    switch event.kind {
    case .resourceUpdated:
        if let title = event.payload["title"]?.stringValue {
            return "Notebook updated '\(title)'"
        }
        return "Notebook updated a note"
    case .actionCompleted:
        return event.payload["message"]?.stringValue
    default:
        return nil
    }
}
