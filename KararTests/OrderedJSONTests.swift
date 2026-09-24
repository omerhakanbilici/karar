import XCTest
@testable import Karar

final class OrderedJSONTests: XCTestCase {
    func testMembersKeepDocumentOrderAndTheirValues() {
        let json = #"{"b": {"x": [1, 2]}, "a" : "s,}\"", "c":null}"#
        let members = OrderedJSON.members(of: Data(json.utf8))
        XCTAssertEqual(members.map(\.key), ["b", "a", "c"])
        XCTAssertEqual(members.map { String(decoding: $0.value, as: UTF8.self).trimmingCharacters(in: .whitespaces) },
                       [#"{"x": [1, 2]}"#, #""s,}\"""#, "null"])
    }

    func testMembersOfSomethingElseAreEmpty() {
        XCTAssertTrue(OrderedJSON.members(of: Data("[1, 2]".utf8)).isEmpty)
        XCTAssertTrue(OrderedJSON.members(of: Data(#""a:b""#.utf8)).isEmpty)
    }

    func testPrettyKeepsOrderAndNumbers() {
        let json = #"{"b":{"x":0.3237,"e":{},"s":"a,{\"b"},"a":[1,2],"z":[]}"#
        XCTAssertEqual(OrderedJSON.pretty(Data(json.utf8)), #"""
        {
          "b": {
            "x": 0.3237,
            "e": {},
            "s": "a,{\"b"
          },
          "a": [
            1,
            2
          ],
          "z": []
        }
        """#)
    }
}
