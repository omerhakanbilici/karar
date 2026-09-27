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
                            ("THIRD_PARTY_NOTICES", "Ollaya"), ("onnxruntime-ThirdPartyNotices.txt", "Ollaya"),
                            ("mlx-THIRD_PARTY_NOTICES", "Ollaya")] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil, subdirectory: dir), "\(dir ?? "")/\(name)")
        }
    }

    /// The runner looks for MLX's kernels at <exe dir>/../Resources/mlx_metal/ in an app bundle;
    /// without them laya runs on the CPU (spec 2026-09-26 §3.2).
    func testMLXKernelsShipWhereTheRunnerLooks() {
        XCTAssertNotNil(Bundle.main.url(forResource: "mlx", withExtension: "metallib", subdirectory: "mlx_metal"))
    }
}
