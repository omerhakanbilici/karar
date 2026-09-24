import XCTest
@testable import Karar

final class SmokeTests: XCTestCase {
    func testOllayaIsEmbedded() throws {
        // Tests run inside the app (TEST_HOST), so Bundle.main is Karar.app.
        let ollaya = try XCTUnwrap(Bundle.main.url(forAuxiliaryExecutable: "ollaya"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: ollaya.path), ollaya.path)
    }

    func testBundledOllayaVersionIsReadable() {
        XCTAssertTrue(Daemon.bundledVersion.hasPrefix("v"), Daemon.bundledVersion)
    }
}
