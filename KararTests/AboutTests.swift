import XCTest
@testable import Karar

@MainActor
final class AboutTests: XCTestCase {
    func testModelLicencesComeFromTheCatalog() {
        let licences = AboutView.modelLicences
        XCTAssertEqual(licences.map(\.licence), ["Apache-2.0", "MIT"])
        XCTAssertEqual(licences.first?.models.first, "laya", "catalog order")
        XCTAssertEqual(licences.last?.models, ["nli"])
    }

    func testTheLicenceTextsShipInTheApp() {
        for (name, dir) in [("LICENSE", nil), ("NOTICE", nil), ("LICENSE", "Ollaya"),
                            ("THIRD_PARTY_NOTICES", "Ollaya"), ("onnxruntime-ThirdPartyNotices.txt", "Ollaya")] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil, subdirectory: dir), "\(dir ?? "")/\(name)")
        }
    }
}
