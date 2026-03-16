import XCTest
@testable import Fabric
@testable import FabricShowcaseSupport

final class FabricShowcaseSupportTests: XCTestCase {
    func testBacklinksGroupNotesBySourceURIAndSortByTitle() {
        let resources: [FabricResourceDescriptor] = [
            FabricResourceDescriptor(
                uri: ShowcaseURIs.note("note-2"),
                kind: ShowcaseResourceKinds.note,
                title: "Zeta Note",
                summary: "Later note",
                capabilities: [.read],
                metadata: [
                    ShowcaseMetadataKeys.sourceURI: .string(ShowcaseURIs.tab("tab-1").rawValue),
                    ShowcaseMetadataKeys.sourceURL: .string("https://example.com/one"),
                ]
            ),
            FabricResourceDescriptor(
                uri: ShowcaseURIs.note("note-1"),
                kind: ShowcaseResourceKinds.note,
                title: "Alpha Note",
                summary: "Earlier note",
                capabilities: [.read],
                metadata: [
                    ShowcaseMetadataKeys.sourceURI: .string(ShowcaseURIs.tab("tab-1").rawValue),
                    ShowcaseMetadataKeys.sourceURL: .string("https://example.com/one"),
                ]
            ),
            FabricResourceDescriptor(
                uri: ShowcaseURIs.note("note-3"),
                kind: ShowcaseResourceKinds.note,
                title: "Standalone",
                summary: "No source",
                capabilities: [.read]
            ),
        ]

        let backlinks = showcaseBacklinks(from: resources)

        XCTAssertEqual(
            backlinks[ShowcaseURIs.tab("tab-1").rawValue],
            [
                ShowcaseNoteLink(id: "note-1", title: "Alpha Note"),
                ShowcaseNoteLink(id: "note-2", title: "Zeta Note"),
            ]
        )
        XCTAssertNil(backlinks["standalone"])
    }

    func testSourceMetadataRoundTrips() {
        let source = ShowcaseNoteSource(
            uri: ShowcaseURIs.currentSelection.rawValue,
            url: "https://example.com/fabric",
            capturedSelection: "local context substrate"
        )

        let metadata = showcaseMetadata(for: source)

        XCTAssertEqual(showcaseSource(from: metadata), source)
    }
}
