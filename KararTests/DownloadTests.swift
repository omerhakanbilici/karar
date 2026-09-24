import XCTest
@testable import Karar

final class DownloadTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func manifest() -> PullProgress { PullProgress(status: "pulling manifest", digest: nil, total: nil, completed: nil) }
    private func layer(_ digest: String, _ total: Int64, _ completed: Int64) -> PullProgress {
        PullProgress(status: "pulling \(digest)", digest: "sha256:\(digest)", total: total, completed: completed)
    }
    private func status(_ s: String) -> PullProgress { PullProgress(status: s, digest: nil, total: nil, completed: nil) }

    func testASingleModelHasOnePartThatUsesTheEstimateUntilDone() throws {
        let entry = try XCTUnwrap(CatalogEntry.named("laya:en"))
        var d = Download(for: entry)
        XCTAssertEqual(d.parts.map(\.name), ["laya:en"])
        d.apply(manifest(), at: t0)
        d.apply(layer("a", 400, 400), at: t0)
        XCTAssertEqual(d.parts[0].completed, 400)
        XCTAssertEqual(d.parts[0].total, entry.size, "not 400: more blobs are coming")
        d.apply(layer("b", 1000, 500), at: t0)
        d.apply(layer("b", 1000, 1000), at: t0)
        XCTAssertEqual(d.parts[0].completed, 1400, "a repeated blob line replaces, not adds")
        d.apply(status("verifying sha256 digest"), at: t0)
        d.apply(status("writing manifest"), at: t0)
        XCTAssertFalse(d.isFinished)
        d.apply(status("success"), at: t0)
        XCTAssertTrue(d.isFinished)
        XCTAssertTrue(d.parts[0].isDone)
        XCTAssertEqual(d.parts[0].total, 1400)
        XCTAssertEqual(d.fraction, 1)
    }

    func testARouterGetsOneBarPerTargetAndNoneForItself() throws {
        var d = Download(for: try XCTUnwrap(CatalogEntry.named("laya")))
        XCTAssertEqual(d.parts.map(\.name), ["laya:en", "laya:multilingual"])
        d.apply(manifest(), at: t0)                 // the router's own manifest
        d.apply(layer("r", 135, 135), at: t0)
        XCTAssertEqual(d.parts.map(\.completed), [0, 0])
        d.apply(manifest(), at: t0)                 // laya:en
        d.apply(layer("e", 800, 800), at: t0)
        d.apply(manifest(), at: t0)                 // laya:multilingual
        XCTAssertTrue(d.parts[0].isDone)
        XCTAssertEqual(d.parts[0].total, 800)
        d.apply(layer("m", 600, 300), at: t0)
        XCTAssertEqual(d.parts[1].completed, 300)
        XCTAssertFalse(d.parts[1].isDone)
    }

    func testSpeedIgnoresBytesAlreadyOnDiskAndETAUsesIt() throws {
        let entry = try XCTUnwrap(CatalogEntry.named("laya:multilingual"))
        var d = Download(for: entry)
        d.apply(manifest(), at: t0)
        d.apply(layer("w", 600_000_000, 0), at: t0)
        d.apply(layer("w", 600_000_000, 400_000_000), at: t0.addingTimeInterval(0.1))   // resumed
        XCTAssertNil(d.bytesPerSecond, "no speed in the first second")
        d.apply(layer("w", 600_000_000, 440_000_000), at: t0.addingTimeInterval(2.1))
        XCTAssertEqual(try XCTUnwrap(d.bytesPerSecond), 20_000_000, accuracy: 1)
        let left = try XCTUnwrap(d.secondsLeft(d.parts[0]))
        XCTAssertEqual(left, Double(entry.size - 440_000_000) / 20_000_000, accuracy: 0.01)
    }

    func testOverallFractionCoversEveryPart() throws {
        var d = Download(for: try XCTUnwrap(CatalogEntry.named("laya")))
        d.apply(manifest(), at: t0)
        d.apply(manifest(), at: t0)
        d.apply(layer("e", 853_634_822, 853_634_822), at: t0)
        let expected = 853_634_822.0 / Double(853_634_822 + 684_161_400)
        XCTAssertEqual(d.fraction, expected, accuracy: 0.0001)
    }
}
