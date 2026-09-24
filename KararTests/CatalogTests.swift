import XCTest
@testable import Karar

final class CatalogTests: XCTestCase {
    func testBundlesTheCatalogWithLayaRecommendedFirst() {
        let names = CatalogEntry.all.map(\.name)
        XCTAssertEqual(names, ["laya", "laya:multilingual", "laya:en", "laya:typed-decisions",
                               "nli:modernbert-large", "nli", "gliclass", "decider:0.8b", "decider"])
        XCTAssertEqual(CatalogEntry.all.filter(\.recommended).map(\.name), ["laya"])
        for entry in CatalogEntry.all {
            XCTAssertFalse(entry.summary.isEmpty, entry.name)
            XCTAssertFalse(entry.languages.isEmpty, entry.name)
            XCTAssertFalse(entry.license.isEmpty, entry.name)
            XCTAssertGreaterThan(entry.size, 100_000_000, entry.name)
        }
    }

    func testCanonicalNamesMatchTags() {
        XCTAssertEqual(CatalogEntry.named("laya")?.canonicalName, "laya:latest")
        XCTAssertEqual(CatalogEntry.named("laya:en")?.canonicalName, "laya:en")
    }

    func testTheRouterIncludesItsTargetsInRouteOrder() throws {
        let laya = try XCTUnwrap(CatalogEntry.named("laya"))
        XCTAssertEqual(laya.includes, ["laya:en", "laya:multilingual"])
        XCTAssertEqual(laya.size, laya.includes.compactMap { CatalogEntry.named($0)?.size }.reduce(10_730, +))
        XCTAssertTrue(CatalogEntry.all.filter { $0.name != "laya" }.allSatisfy(\.includes.isEmpty))
    }
}
