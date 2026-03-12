import XCTest
@testable import Fabric

final class FabricDescriptorCodingTests: XCTestCase {
    func testResourceDescriptorCodableRoundTripsPresentation() throws {
        let descriptor = FabricResourceDescriptor(
            uri: FabricURI(appID: "wheel.browser", kind: "tab", id: "123"),
            kind: "tab",
            title: "Docs",
            summary: "https://example.com/docs",
            capabilities: [.read, .mention],
            metadata: ["url": .string("https://example.com/docs")],
            presentation: FabricPresentationHints(
                systemImage: "square.on.square",
                tint: "blue",
                subtitle: "example.com",
                categoryLabel: "Tab"
            )
        )

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(FabricResourceDescriptor.self, from: data)

        XCTAssertEqual(decoded, descriptor)
        XCTAssertEqual(decoded.presentation?.systemImage, "square.on.square")
        XCTAssertEqual(decoded.presentation?.tint, "blue")
    }

    func testContextPayloadCodablePreservesMissingPresentation() throws {
        let payload = FabricContextPayload(
            uri: FabricURI(appID: "wheel.notes", kind: "note", id: "abc"),
            kind: "note",
            title: "Planning",
            body: "Ship generic Fabric mentions.",
            metadata: ["noteID": .string("abc")]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(FabricContextPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertNil(decoded.presentation)
    }
}
