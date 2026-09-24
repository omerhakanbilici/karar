import XCTest
@testable import Karar

final class PresetTests: XCTestCase {
    func testBundlesEveryPresetInPickerOrder() throws {
        XCTAssertEqual(Preset.all.map(\.id), ["triage", "email", "guard", "moderation", "router"])
        XCTAssertEqual(Preset.all.map(\.name), ["Support ticket", "Email", "Safety", "Moderation", "Routing"])
        for preset in Preset.all {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: preset.questions) as? [String: Any], preset.id)
            XCTAssertEqual(Set(preset.questionIDs), Set(object.keys), preset.id)
            XCTAssertEqual(preset.questionIDs.count, object.count, preset.id)
            XCTAssertFalse(preset.hint.isEmpty, preset.id)
        }
    }

    func testTriageQuestionsKeepFileOrder() {
        XCTAssertEqual(Preset.all[0].questionIDs,
                       ["intent", "is_urgent", "frustration", "refund_requested", "churn_risk"])
    }

    func testTopLevelKeysSkipNestedKeysAndStringContents() {
        let json = #"{"b": {"a": 1, "x:y": "}"}, "a\"q": [1, {"z": 2}], "c": "d:e", "ç": null}"#
        XCTAssertEqual(Preset.topLevelKeys(of: Data(json.utf8)), ["b", "a\"q", "c", "ç"])
    }
}
