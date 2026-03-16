import Foundation
import Fabric

public actor ShowcaseBrowserApp: FabricResourceProvider, FabricSubscriptionProvider {
    public nonisolated let appID = ShowcaseAppIDs.browser

    private var tabs: [ShowcaseBrowserTab]
    private var currentTabID: String
    private var linkedNotesBySourceURI: [String: [ShowcaseNoteLink]]
    private var lastNotebookEvent: String?
    private var fabric: FabricXPCClient?
    private let onSnapshot: ShowcaseBrowserSnapshotHandler

    public init(
        tabs: [ShowcaseBrowserTab] = ShowcaseSeedData.browserTabs,
        onSnapshot: @escaping ShowcaseBrowserSnapshotHandler = { _ in }
    ) {
        self.tabs = tabs
        self.currentTabID = tabs.first?.id ?? "tab-1"
        self.linkedNotesBySourceURI = [:]
        self.onSnapshot = onSnapshot
    }

    public func attach(client: FabricXPCClient) async {
        self.fabric = client
        await publishSnapshot()
    }

    public func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
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

    public func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        switch uri.kind {
        case ShowcaseResourceKinds.page:
            guard uri.id == "current", let currentTab else { return nil }
            return FabricContextPayload(
                uri: ShowcaseURIs.currentPage,
                kind: ShowcaseResourceKinds.page,
                title: currentTab.title,
                body: currentTab.body,
                metadata: [
                    "url": .string(currentTab.url),
                    "tabID": .string(currentTab.id),
                    "source": .string("current-page"),
                ]
            )

        case ShowcaseResourceKinds.selection:
            guard uri.id == "current",
                  let currentTab,
                  let selectedText = currentTab.selectedText,
                  !selectedText.isEmpty else {
                return nil
            }

            return FabricContextPayload(
                uri: ShowcaseURIs.currentSelection,
                kind: ShowcaseResourceKinds.selection,
                title: "Selection from \(currentTab.title)",
                body: selectedText,
                metadata: [
                    "url": .string(currentTab.url),
                    "tabID": .string(currentTab.id),
                    "source": .string("selection"),
                ]
            )

        case ShowcaseResourceKinds.tab:
            guard let tab = tabs.first(where: { $0.id == uri.id }) else { return nil }
            return FabricContextPayload(
                uri: ShowcaseURIs.tab(tab.id),
                kind: ShowcaseResourceKinds.tab,
                title: tab.title,
                body: tab.body,
                metadata: [
                    "url": .string(tab.url),
                    "tabID": .string(tab.id),
                    "source": .string("tab"),
                ]
            )

        default:
            return nil
        }
    }

    public func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let appID = request.appID, appID != self.appID {
            throw FabricError.unsupportedSubscription(
                "showcase.browser cannot validate subscription for \(appID)"
            )
        }
    }

    public func setCurrentTab(id: String) async throws {
        guard tabs.contains(where: { $0.id == id }) else { return }
        currentTabID = id
        await publishSnapshot()

        guard let fabric, let currentTab else { return }

        try await fabric.publish(
            event: FabricEvent(
                appID: appID,
                kind: .currentPageChanged,
                resourceURI: ShowcaseURIs.currentPage,
                resourceKind: ShowcaseResourceKinds.page,
                payload: [
                    "tabID": .string(currentTab.id),
                    "title": .string(currentTab.title),
                    "url": .string(currentTab.url),
                ]
            ),
            from: appID
        )

        try await fabric.publish(
            event: FabricEvent(
                appID: appID,
                kind: .selectionChanged,
                resourceURI: ShowcaseURIs.currentSelection,
                resourceKind: ShowcaseResourceKinds.selection,
                payload: [
                    "tabID": .string(currentTab.id),
                    "hasSelection": .bool(!(currentTab.selectedText ?? "").isEmpty),
                    "selection": .string(currentTab.selectedText ?? ""),
                ]
            ),
            from: appID
        )
    }

    public func refreshBacklinks(
        from resources: [FabricResourceDescriptor],
        noteEvent: FabricEvent? = nil
    ) async {
        linkedNotesBySourceURI = showcaseBacklinks(from: resources)
        if let noteEvent {
            lastNotebookEvent = showcaseNotebookEventMessage(from: noteEvent)
        }
        await publishSnapshot()
    }

    public func selectedTab() -> ShowcaseBrowserTab? {
        currentTab
    }

    private var currentTab: ShowcaseBrowserTab? {
        tabs.first(where: { $0.id == currentTabID })
    }

    private func resourceCatalog() -> [FabricResourceDescriptor] {
        var resources = tabs.map { tab in
            FabricResourceDescriptor(
                uri: ShowcaseURIs.tab(tab.id),
                kind: ShowcaseResourceKinds.tab,
                title: tab.title,
                summary: tab.url,
                capabilities: [.read, .mention],
                metadata: [
                    "url": .string(tab.url),
                    "tabID": .string(tab.id),
                ]
            )
        }

        if let currentTab {
            resources.insert(
                FabricResourceDescriptor(
                    uri: ShowcaseURIs.currentPage,
                    kind: ShowcaseResourceKinds.page,
                    title: "Current Page",
                    summary: currentTab.title,
                    capabilities: [.read, .mention, .subscribe],
                    metadata: [
                        "url": .string(currentTab.url),
                        "tabID": .string(currentTab.id),
                    ]
                ),
                at: 0
            )

            if let selectedText = currentTab.selectedText, !selectedText.isEmpty {
                resources.insert(
                    FabricResourceDescriptor(
                        uri: ShowcaseURIs.currentSelection,
                        kind: ShowcaseResourceKinds.selection,
                        title: "Current Selection",
                        summary: selectedText,
                        capabilities: [.read, .mention, .subscribe],
                        metadata: [
                            "url": .string(currentTab.url),
                            "tabID": .string(currentTab.id),
                        ]
                    ),
                    at: 1
                )
            }
        }

        return resources
    }

    private func publishSnapshot() async {
        await onSnapshot(
            ShowcaseBrowserSnapshot(
                tabs: tabs,
                currentTabID: currentTabID,
                linkedNotesBySourceURI: linkedNotesBySourceURI,
                lastNotebookEvent: lastNotebookEvent
            )
        )
    }
}
