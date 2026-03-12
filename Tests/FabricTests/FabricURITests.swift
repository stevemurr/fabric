import XCTest
@testable import Fabric

final class FabricURITests: XCTestCase {
    func testFabricURIParsesCanonicalForm() throws {
        let uri = try FabricURI(string: "fabric://wheel/tab/tab-1")

        XCTAssertEqual(uri.appID, "wheel")
        XCTAssertEqual(uri.kind, "tab")
        XCTAssertEqual(uri.id, "tab-1")
        XCTAssertEqual(uri.rawValue, "fabric://wheel/tab/tab-1")
    }

    func testFabricURIRejectsInvalidForm() {
        XCTAssertThrowsError(try FabricURI(string: "https://wheel/tab/tab-1"))
        XCTAssertThrowsError(try FabricURI(string: "fabric://wheel"))
    }
}
