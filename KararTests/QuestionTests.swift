import XCTest
@testable import Karar

final class QuestionTests: XCTestCase {
    func testEveryPresetSurvivesARoundTrip() throws {
        for preset in Preset.all {
            let questions = Question.parse(preset.questions)
            XCTAssertEqual(questions.map(\.key), preset.questionIDs, preset.id)
            let written = Question.json(questions)
            XCTAssertEqual(OrderedJSON.members(of: written).map(\.key), preset.questionIDs, preset.id)
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: preset.questions) as? NSDictionary)
            let copy = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? NSDictionary, String(decoding: written, as: UTF8.self))
            XCTAssertEqual(copy, original, preset.id)
        }
    }

    func testParseKeepsOptionOrderAndReadsEveryKind() {
        let triage = Question.parse(Preset.all[0].questions)
        XCTAssertEqual(triage[0].kind, .choice)
        XCTAssertEqual(triage[0].options.map(\.label),
                       ["refund", "technical_help", "billing_question", "information", "cancellation", "other"])
        XCTAssertEqual(triage[0].options[0].text, "money returned or a duplicate charge reversed")
        XCTAssertEqual(triage[2].kind, .score)
        XCTAssertEqual(triage[2].options.map(\.text).first, "calm and neutral")
        XCTAssertEqual(triage[1].kind, .noul)
        XCTAssertEqual(triage[1].options.map(\.label), ["true", "false"])
        XCTAssertEqual(triage[1].instructions, "Does `message` communicate time pressure or a deadline?")
    }

    func testChoiceLabelsMayBeAnArray() {
        let questions = Question.parse(Data(#"{"tone": {"type": "choice", "criteria": ["calm", "angry"]}}"#.utf8))
        XCTAssertEqual(questions.first?.options.map(\.label), ["calm", "angry"])
        XCTAssertEqual(questions.first?.instructions, "")
    }

    func testJSONLeavesOutWhatIsEmpty() throws {
        var noul = Question(key: "is_spam", kind: .noul)
        var choice = Question(key: "tone", kind: .choice)
        choice.options[1].text = "angry words"
        noul.options[0].text = "bulk mail"
        var score = Question(key: "urgency", kind: .score)
        score.instructions = "How urgent?"
        let json = Question.json([noul, choice, score])
        XCTAssertEqual(String(decoding: json, as: UTF8.self), #"""
        {"is_spam":{"type":"noul","criteria":{"true":"bulk mail"}},"tone":{"type":"choice","criteria":{"option_1":null,"option_2":"angry words"}},"urgency":{"type":"score","instructions":"How urgent?","criteria":["low","medium","high"]}}
        """#)
    }

    func testChangingTheKindResetsTheOptions() {
        var question = Question(key: "q", kind: .choice)
        question.options.append(.init(label: "third"))
        question.change(to: .noul)
        XCTAssertEqual(question.kind, .noul)
        XCTAssertEqual(question.options.map(\.label), ["true", "false"])
        question.change(to: .noul)
        XCTAssertEqual(question.options.count, 2)
    }

    func testDuplicateKeys() {
        let questions = [Question(key: "a", kind: .noul), Question(key: "b", kind: .noul), Question(key: "a", kind: .score)]
        XCTAssertEqual(Question.duplicateKeys(questions), ["a"])
        XCTAssertEqual(Question.duplicateKeys(Array(questions.prefix(2))), [])
    }

    func testRawTextShowsTheEnginesNumbers() {
        XCTAssertEqual(Answer(type: "choice", choice: "billing", score: nil, noul: nil, confidence: 0.7781, probabilities: nil).rawText,
                       "billing · confidence 0.78")
        XCTAssertEqual(Answer(type: "score", choice: nil, score: 1.1982, noul: nil, confidence: 0.3418, probabilities: nil).rawText,
                       "1.20 · confidence 0.34")
        XCTAssertEqual(Answer(type: "noul", choice: nil, score: nil, noul: 0.9127, confidence: nil, probabilities: nil).rawText,
                       "0.91")
    }
}
