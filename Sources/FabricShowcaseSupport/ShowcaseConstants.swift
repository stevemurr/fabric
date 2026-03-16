import Foundation
import Fabric

public enum ShowcaseRole: String, Sendable, CaseIterable {
    case browser
    case notes
    case lens
}

public enum ShowcaseAppIDs {
    public static let browser = "showcase.browser"
    public static let notes = "showcase.notes"
    public static let chat = "showcase.chat"
}

public enum ShowcaseActionIDs {
    public static let createNote = "showcase.notes.create-note"
    public static let appendToNote = "showcase.notes.append-to-note"
    public static let openNote = "showcase.notes.open-note"
}

public enum ShowcaseResourceKinds {
    public static let page = "page"
    public static let selection = "selection"
    public static let tab = "tab"
    public static let note = "note"
}

public enum ShowcaseMetadataKeys {
    public static let sourceURI = "sourceURI"
    public static let sourceURL = "sourceURL"
    public static let capturedSelection = "capturedSelection"
}

public enum ShowcaseURIs {
    public static let currentPage = FabricURI(
        appID: ShowcaseAppIDs.browser,
        kind: ShowcaseResourceKinds.page,
        id: "current"
    )
    public static let currentSelection = FabricURI(
        appID: ShowcaseAppIDs.browser,
        kind: ShowcaseResourceKinds.selection,
        id: "current"
    )

    public static func tab(_ id: String) -> FabricURI {
        FabricURI(appID: ShowcaseAppIDs.browser, kind: ShowcaseResourceKinds.tab, id: id)
    }

    public static func note(_ id: String) -> FabricURI {
        FabricURI(appID: ShowcaseAppIDs.notes, kind: ShowcaseResourceKinds.note, id: id)
    }
}
