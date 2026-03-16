import AppKit
import Combine
import Fabric
import FabricGateway
import FabricShowcaseSupport
import SwiftUI

@main
struct FabricShowcaseApp: App {
    @NSApplicationDelegateAdaptor(ShowcaseAppDelegate.self) private var appDelegate
    private let role = ShowcaseRoleResolver.resolve()

    var body: some Scene {
        WindowGroup(role.windowTitle) {
            switch role {
            case .browser:
                BrowserWindow()
            case .notes:
                NotesWindow()
            case .lens:
                LensWindow()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: role.defaultSize.width, height: role.defaultSize.height)
    }
}

private final class ShowcaseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum ShowcaseRoleResolver {
    static func resolve(arguments: [String] = CommandLine.arguments) -> ShowcaseRole {
        guard let index = arguments.firstIndex(of: "--role"),
              arguments.indices.contains(index + 1),
              let role = ShowcaseRole(rawValue: arguments[index + 1].lowercased()) else {
            return .browser
        }

        return role
    }
}

private extension ShowcaseRole {
    var windowTitle: String {
        switch self {
        case .browser:
            return "Fabric Showcase Browser"
        case .notes:
            return "Fabric Showcase Notebook"
        case .lens:
            return "Fabric Showcase Lens"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .browser:
            return .init(width: 1080, height: 720)
        case .notes:
            return .init(width: 1180, height: 760)
        case .lens:
            return .init(width: 1260, height: 760)
        }
    }
}

@MainActor
private final class BrowserCoordinator: ObservableObject {
    @Published private(set) var snapshot = ShowcaseBrowserSnapshot(
        tabs: ShowcaseSeedData.browserTabs,
        currentTabID: ShowcaseSeedData.browserTabs.first?.id ?? "",
        linkedNotesBySourceURI: [:]
    )
    @Published var errorMessage: String?
    @Published var connected = false

    private var browserApp: ShowcaseBrowserApp?
    private var client: FabricXPCClient?
    private var notesSubscriptionTask: Task<Void, Never>?
    private var started = false

    var currentTab: ShowcaseBrowserTab? {
        snapshot.tabs.first(where: { $0.id == snapshot.currentTabID })
    }

    func linkedNotes(for tab: ShowcaseBrowserTab) -> [ShowcaseNoteLink] {
        snapshot.linkedNotesBySourceURI[ShowcaseURIs.tab(tab.id).rawValue] ?? []
    }

    func start() async {
        guard !started else { return }
        started = true

        let app = ShowcaseBrowserApp { [weak self] snapshot in
            await MainActor.run {
                self?.snapshot = snapshot
            }
        }
        let client = FabricXPCClient(
            resourceProvider: AnyFabricResourceProvider(app),
            subscriptionProvider: AnyFabricSubscriptionProvider(app)
        )

        browserApp = app
        self.client = client
        await app.attach(client: client)

        do {
            try await client.register(
                appID: ShowcaseAppIDs.browser,
                exposesResources: true,
                exposesActions: false,
                exposesSubscriptions: true
            )
            connected = true
            errorMessage = nil
            await refreshBacklinks()
        } catch {
            errorMessage = error.localizedDescription
        }

        startNotesSubscriptionLoop()
    }

    func select(tabID: String) {
        guard let browserApp else { return }

        Task {
            do {
                try await browserApp.setCurrentTab(id: tabID)
                await MainActor.run {
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startNotesSubscriptionLoop() {
        guard notesSubscriptionTask == nil else { return }

        notesSubscriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }

                do {
                    let subscription = try await client.subscribe(
                        callerAppID: ShowcaseAppIDs.browser,
                        request: FabricSubscriptionRequest(
                            appID: ShowcaseAppIDs.notes,
                            resourceKind: ShowcaseResourceKinds.note,
                            eventKinds: [.resourceUpdated, .actionCompleted]
                        )
                    )

                    for await event in subscription.stream {
                        guard !Task.isCancelled else {
                            await subscription.cancel()
                            return
                        }

                        await self.refreshBacklinks(noteEvent: event)
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func refreshBacklinks(noteEvent: FabricEvent? = nil) async {
        guard let client, let browserApp else { return }

        do {
            let resources = try await client.discoverResources(callerAppID: ShowcaseAppIDs.browser)
            let noteResources = resources.filter {
                $0.uri.appID == ShowcaseAppIDs.notes && $0.kind == ShowcaseResourceKinds.note
            }
            await browserApp.refreshBacklinks(from: noteResources, noteEvent: noteEvent)
            await MainActor.run {
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
private final class NotesCoordinator: ObservableObject {
    @Published private(set) var snapshot = ShowcaseNotesSnapshot(
        notes: ShowcaseSeedData.notes,
        currentPage: nil,
        currentSelection: nil
    )
    @Published var selectedNoteID: String? = ShowcaseSeedData.notes.first?.id
    @Published var errorMessage: String?
    @Published var connected = false

    private var notesApp: ShowcaseNotesApp?
    private var client: FabricXPCClient?
    private var browserSubscriptionTask: Task<Void, Never>?
    private var started = false

    var selectedNote: ShowcaseNote? {
        snapshot.notes.first(where: { $0.id == selectedNoteID })
    }

    func start() async {
        guard !started else { return }
        started = true

        let app = ShowcaseNotesApp { [weak self] snapshot in
            await MainActor.run {
                self?.snapshot = snapshot
                if self?.selectedNoteID == nil || snapshot.notes.contains(where: { $0.id == self?.selectedNoteID }) == false {
                    self?.selectedNoteID = snapshot.notes.first?.id
                }
            }
        }
        let client = FabricXPCClient(
            resourceProvider: AnyFabricResourceProvider(app),
            actionProvider: AnyFabricActionProvider(app),
            subscriptionProvider: AnyFabricSubscriptionProvider(app)
        )

        notesApp = app
        self.client = client
        await app.attach(client: client)

        do {
            try await client.register(
                appID: ShowcaseAppIDs.notes,
                exposesResources: true,
                exposesActions: true,
                exposesSubscriptions: true
            )
            connected = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        await refreshLiveContext(status: "Waiting for browser context")
        startBrowserSubscriptionLoop()
    }

    func select(noteID: String) {
        selectedNoteID = noteID
    }

    func createResearchNote() {
        Task {
            await performCreateResearchNote()
        }
    }

    func captureSelection() {
        Task {
            await performCaptureSelection()
        }
    }

    private func startBrowserSubscriptionLoop() {
        guard browserSubscriptionTask == nil else { return }

        browserSubscriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }

                do {
                    let subscription = try await client.subscribe(
                        callerAppID: ShowcaseAppIDs.notes,
                        request: FabricSubscriptionRequest(
                            appID: ShowcaseAppIDs.browser,
                            eventKinds: [.currentPageChanged, .selectionChanged]
                        )
                    )

                    for await _ in subscription.stream {
                        guard !Task.isCancelled else {
                            await subscription.cancel()
                            return
                        }

                        await self.refreshLiveContext(status: "Updated from browser")
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func refreshLiveContext(status: String? = nil) async {
        guard let notesApp else { return }

        let page = await resolveOptionalContext(
            callerAppID: ShowcaseAppIDs.notes,
            uri: ShowcaseURIs.currentPage
        )
        let selection = await resolveOptionalContext(
            callerAppID: ShowcaseAppIDs.notes,
            uri: ShowcaseURIs.currentSelection
        )

        await notesApp.refreshLiveContext(page: page, selection: selection)
        if let status {
            await notesApp.updateStatusLine(status)
        }
    }

    private func performCreateResearchNote() async {
        guard let client else { return }
        guard let page = snapshot.currentPage else {
            errorMessage = "No current page context is available yet."
            return
        }

        do {
            let token = try await client.issueConfirmationToken(
                callerAppID: ShowcaseAppIDs.chat,
                calleeAppID: ShowcaseAppIDs.notes,
                actionID: ShowcaseActionIDs.createNote
            )
            let result = try await client.invokeAction(
                callerAppID: ShowcaseAppIDs.chat,
                invocation: FabricActionInvocation(
                    actionID: ShowcaseActionIDs.createNote,
                    arguments: buildCreateNoteArguments(
                        title: "Research: \(page.title)",
                        body: buildResearchBody(page: page, selection: snapshot.currentSelection),
                        page: page,
                        selection: snapshot.currentSelection
                    ),
                    confirmationToken: token
                )
            )

            if let uriString = result.output["noteURI"]?.stringValue,
               let uri = try? FabricURI(string: uriString) {
                selectedNoteID = uri.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performCaptureSelection() async {
        guard let client else { return }
        guard let selection = snapshot.currentSelection else {
            errorMessage = "Select some browser text to capture it into a note."
            return
        }

        do {
            if let selectedNote {
                let token = try await client.issueConfirmationToken(
                    callerAppID: ShowcaseAppIDs.chat,
                    calleeAppID: ShowcaseAppIDs.notes,
                    actionID: ShowcaseActionIDs.appendToNote
                )

                _ = try await client.invokeAction(
                    callerAppID: ShowcaseAppIDs.chat,
                    invocation: FabricActionInvocation(
                        actionID: ShowcaseActionIDs.appendToNote,
                        arguments: [
                            "noteURI": .string(ShowcaseURIs.note(selectedNote.id).rawValue),
                            "content": .string(
                                """
                                Capture from Browser
                                \(selection.body)
                                """
                            ),
                        ],
                        confirmationToken: token
                    )
                )
            } else if let page = snapshot.currentPage {
                let token = try await client.issueConfirmationToken(
                    callerAppID: ShowcaseAppIDs.chat,
                    calleeAppID: ShowcaseAppIDs.notes,
                    actionID: ShowcaseActionIDs.createNote
                )

                let result = try await client.invokeAction(
                    callerAppID: ShowcaseAppIDs.chat,
                    invocation: FabricActionInvocation(
                        actionID: ShowcaseActionIDs.createNote,
                        arguments: buildCreateNoteArguments(
                            title: "Capture: \(page.title)",
                            body: selection.body,
                            page: page,
                            selection: selection
                        ),
                        confirmationToken: token
                    )
                )

                if let uriString = result.output["noteURI"]?.stringValue,
                   let uri = try? FabricURI(string: uriString) {
                    selectedNoteID = uri.id
                }
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildCreateNoteArguments(
        title: String,
        body: String,
        page: FabricContextPayload,
        selection: FabricContextPayload?
    ) -> FabricMetadata {
        var arguments: FabricMetadata = [
            "title": .string(title),
            "body": .string(body),
        ]

        let source = sourceForCurrentContext(page: page, selection: selection)
        for (key, value) in showcaseMetadata(for: source) {
            arguments[key] = value
        }

        return arguments
    }

    private func sourceForCurrentContext(
        page: FabricContextPayload,
        selection: FabricContextPayload?
    ) -> ShowcaseNoteSource {
        let metadata = selection?.metadata ?? page.metadata
        let tabID = metadata["tabID"]?.stringValue ?? "current"
        let url = metadata["url"]?.stringValue ?? ""

        return ShowcaseNoteSource(
            uri: ShowcaseURIs.tab(tabID).rawValue,
            url: url,
            capturedSelection: selection?.body
        )
    }

    private func buildResearchBody(
        page: FabricContextPayload,
        selection: FabricContextPayload?
    ) -> String {
        let url = page.metadata["url"]?.stringValue ?? ""
        var sections = [
            "Source",
            url,
            "",
            page.body,
        ]

        if let selection {
            sections.append("")
            sections.append("Current Selection")
            sections.append(selection.body)
        }

        return sections.joined(separator: "\n")
    }

    private func resolveOptionalContext(
        callerAppID: String,
        uri: FabricURI
    ) async -> FabricContextPayload? {
        guard let client else { return nil }

        do {
            return try await client.resolveContexts(callerAppID: callerAppID, uris: [uri]).first
        } catch {
            return nil
        }
    }
}

private struct LensLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let title: String
    let detail: String
}

@MainActor
private final class LensCoordinator: ObservableObject {
    @Published private(set) var resources: [FabricMCPResource] = []
    @Published private(set) var tools: [FabricMCPTool] = []
    @Published private(set) var logEntries: [LensLogEntry] = []
    @Published var errorMessage: String?

    private var client: FabricXPCClient?
    private var gateway: FabricXPCGateway?
    private var browserSubscriptionTask: Task<Void, Never>?
    private var notesSubscriptionTask: Task<Void, Never>?
    private var started = false

    func start() async {
        guard !started else { return }
        started = true

        let client = FabricXPCClient()
        self.client = client
        self.gateway = FabricXPCGateway(client: client)

        await refresh()
        startSubscriptionLoop(
            appID: ShowcaseAppIDs.browser,
            eventKinds: [.currentPageChanged, .selectionChanged]
        )
        startSubscriptionLoop(
            appID: ShowcaseAppIDs.notes,
            eventKinds: [.resourceUpdated, .actionCompleted]
        )
    }

    func refresh() async {
        guard let gateway else { return }

        do {
            resources = try await gateway.listResources(callerAppID: ShowcaseAppIDs.chat)
            tools = try await gateway.listTools(callerAppID: ShowcaseAppIDs.chat)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNoteFromCurrentPage() {
        Task {
            await performCreateNoteFromCurrentPage()
        }
    }

    private func startSubscriptionLoop(
        appID: String,
        eventKinds: Set<FabricEventKind>
    ) {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }

                do {
                    let subscription = try await client.subscribe(
                        callerAppID: ShowcaseAppIDs.chat,
                        request: FabricSubscriptionRequest(
                            appID: appID,
                            eventKinds: eventKinds
                        )
                    )

                    for await event in subscription.stream {
                        guard !Task.isCancelled else {
                            await subscription.cancel()
                            return
                        }

                        await MainActor.run {
                            self.logEntries.insert(
                                LensLogEntry(
                                    title: "\(event.appID) \(event.kind.rawValue)",
                                    detail: event.payload.description
                                ),
                                at: 0
                            )
                        }
                        await self.refresh()
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        if appID == ShowcaseAppIDs.browser {
            browserSubscriptionTask = task
        } else {
            notesSubscriptionTask = task
        }
    }

    private func performCreateNoteFromCurrentPage() async {
        guard let gateway, let client else { return }

        do {
            guard let page = try await client.resolveContexts(
                callerAppID: ShowcaseAppIDs.chat,
                uris: [ShowcaseURIs.currentPage]
            ).first else {
                errorMessage = "Browser context is not available yet."
                return
            }

            let selection = try? await client.resolveContexts(
                callerAppID: ShowcaseAppIDs.chat,
                uris: [ShowcaseURIs.currentSelection]
            ).first

            let tabID = (selection?.metadata["tabID"]?.stringValue)
                ?? page.metadata["tabID"]?.stringValue
                ?? "current"
            let url = (selection?.metadata["url"]?.stringValue)
                ?? page.metadata["url"]?.stringValue
                ?? ""
            let token = try await client.issueConfirmationToken(
                callerAppID: ShowcaseAppIDs.chat,
                calleeAppID: ShowcaseAppIDs.notes,
                actionID: ShowcaseActionIDs.createNote
            )

            let response = try await gateway.callTool(
                callerAppID: ShowcaseAppIDs.chat,
                name: ShowcaseActionIDs.createNote,
                arguments: [
                    "title": .string("Lens Capture: \(page.title)"),
                    "body": .string(
                        """
                        Source
                        \(url)

                        \(page.body)
                        """
                    ),
                    ShowcaseMetadataKeys.sourceURI: .string(ShowcaseURIs.tab(tabID).rawValue),
                    ShowcaseMetadataKeys.sourceURL: .string(url),
                    ShowcaseMetadataKeys.capturedSelection: .string(selection?.body ?? ""),
                ],
                confirmationToken: token
            )

            logEntries.insert(
                LensLogEntry(
                    title: "Tool call \(ShowcaseActionIDs.createNote)",
                    detail: response.structuredContent.description
                ),
                at: 0
            )
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BrowserWindow: View {
    @StateObject private var coordinator = BrowserCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Browser")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Exposes current page, selection, and tabs as Fabric resources.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(
                    title: coordinator.connected ? "Registered" : "Waiting",
                    color: coordinator.connected ? .green : .orange
                )
            }

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(coordinator.snapshot.tabs) { tab in
                            Button {
                                coordinator.select(tabID: tab.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(tab.title)
                                            .font(.headline)
                                        Spacer()
                                        if !coordinator.linkedNotes(for: tab).isEmpty {
                                            Text("\(coordinator.linkedNotes(for: tab).count) notes")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.12), in: Capsule())
                                        }
                                    }

                                    Text(tab.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let selectedText = tab.selectedText {
                                        Text("Selection: \(selectedText)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    tab.id == coordinator.snapshot.currentTabID
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.gray.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .frame(minWidth: 300)

                VStack(alignment: .leading, spacing: 18) {
                    if let currentTab = coordinator.currentTab {
                        Text(currentTab.title)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(currentTab.url)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(currentTab.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                        if let selection = currentTab.selectedText {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Selection")
                                    .font(.headline)
                                Text(selection)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notebook Links")
                                .font(.headline)
                            let linkedNotes = coordinator.linkedNotes(for: currentTab)
                            if linkedNotes.isEmpty {
                                Text("No notes linked to this page yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(linkedNotes) { note in
                                    Text(note.title)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                            }

                            if let lastEvent = coordinator.snapshot.lastNotebookEvent {
                                Text(lastEvent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 680)
        .task {
            await coordinator.start()
        }
    }
}

private struct NotesWindow: View {
    @StateObject private var coordinator = NotesCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notebook")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Consumes browser context and mutates durable notes through Fabric actions.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Create Research Note") {
                        coordinator.createResearchNote()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.snapshot.currentPage == nil)

                    Button("Capture Selection") {
                        coordinator.captureSelection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.snapshot.currentSelection == nil)
                }
            }

            HSplitView {
                List(selection: Binding(
                    get: { coordinator.selectedNoteID },
                    set: { coordinator.selectedNoteID = $0 }
                )) {
                    ForEach(coordinator.snapshot.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.headline)
                            Text(note.body)
                                .lineLimit(2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(note.id))
                    }
                }
                .frame(minWidth: 280)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Live Context")
                            .font(.headline)

                        if let page = coordinator.snapshot.currentPage {
                            contextCard(
                                title: page.title,
                                subtitle: page.metadata["url"]?.stringValue ?? "Current page",
                                body: page.body
                            )
                        } else {
                            emptyCard("Waiting for browser page context.")
                        }

                        if let selection = coordinator.snapshot.currentSelection {
                            contextCard(
                                title: selection.title,
                                subtitle: "Current selection",
                                body: selection.body
                            )
                        } else {
                            emptyCard("No current selection.")
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Selected Note")
                            .font(.headline)

                        if let selectedNote = coordinator.selectedNote {
                            Text(selectedNote.title)
                                .font(.title3.weight(.semibold))
                            ScrollView {
                                Text(selectedNote.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                            if let source = selectedNote.source {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Source")
                                        .font(.caption.weight(.semibold))
                                    Text(source.url)
                                        .font(.caption)
                                    Text(source.uri)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let capturedSelection = source.capturedSelection, !capturedSelection.isEmpty {
                                        Text("Captured selection: \(capturedSelection)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else {
                            emptyCard("Select a note or create one from the current browser context.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let statusLine = coordinator.snapshot.statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 1100, minHeight: 720)
        .task {
            await coordinator.start()
        }
    }
}

private struct LensWindow: View {
    @StateObject private var coordinator = LensCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lens")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("A developer-facing gateway view over the shared Fabric broker.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Refresh") {
                        Task { await coordinator.refresh() }
                    }
                    .buttonStyle(.bordered)

                    Button("Create Note From Current Page") {
                        coordinator.createNoteFromCurrentPage()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Resources")
                        .font(.headline)
                    List(coordinator.resources, id: \.uri) { resource in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resource.title)
                                .font(.headline)
                            Text(resource.uri)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(resource.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 360)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools")
                        .font(.headline)
                    List(coordinator.tools, id: \.name) { tool in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool.name)
                                .font(.headline)
                            Text(tool.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 320)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Event / Call Log")
                        .font(.headline)
                    List(coordinator.logEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title)
                                    .font(.headline)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 360)
            }

            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(minWidth: 1180, minHeight: 720)
        .task {
            await coordinator.start()
        }
    }
}

private func statusBadge(title: String, color: Color) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
}

private func contextCard(title: String, subtitle: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.headline)
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(body)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
}

private func emptyCard(_ message: String) -> some View {
    Text(message)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.secondary)
}
