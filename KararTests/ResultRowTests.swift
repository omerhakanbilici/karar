import XCTest
@testable import Karar

final class ResultRowTests: XCTestCase {
    private func answer(_ type: String, choice: String? = nil, score: Double? = nil, noul: Double? = nil,
                        confidence: Double? = nil, levels: Int? = nil) -> Answer {
        Answer(type: type, choice: choice, score: score, noul: noul, confidence: confidence,
               probabilities: levels.map { n in Dictionary(uniqueKeysWithValues: (0..<n).map { ("\($0)", 1 / Double(n)) }) })
    }

    func testNoulSaysYesOrNoWithTheProbabilityOfThatAnswer() {
        let yes = ResultRow(id: "is_urgent", answer: answer("noul", noul: 0.9127))
        XCTAssertEqual(yes.label, "Is urgent")
        XCTAssertEqual(yes.answer, "Yes")
        XCTAssertEqual(yes.sureness, 0.9127, accuracy: 1e-9)

        let no = ResultRow(id: "is_spam", answer: answer("noul", noul: 0.2))
        XCTAssertEqual(no.answer, "No")
        XCTAssertEqual(no.sureness, 0.8, accuracy: 1e-9)
    }

    func testScoreShowsLevelOutOfTheTopLevel() {
        let row = ResultRow(id: "frustration", answer: answer("score", score: 1.7612, confidence: 0.3418, levels: 4))
        XCTAssertEqual(row.answer, "1.8 / 3")
        XCTAssertEqual(row.sureness, 0.3418)
    }

    func testChoiceShowsTheLabelInWords() {
        let row = ResultRow(id: "intent", answer: answer("choice", choice: "technical_help", confidence: 0.5))
        XCTAssertEqual(row.label, "Intent")
        XCTAssertEqual(row.answer, "Technical help")
        XCTAssertEqual(row.sureness, 0.5)
    }
}
