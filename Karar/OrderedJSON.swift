import Foundation

/// JSON read without losing key order: JSONDecoder and JSONSerialization both drop it, and here
/// order is meaning (question order, option order). Assumes valid JSON.
enum OrderedJSON {
    /// The members of a JSON object in document order, each value as its own JSON text. Anything
    /// that is not an object has no members.
    static func members(of json: Data) -> [(key: String, value: Data)] {
        let bytes = [UInt8](json)
        var members: [(key: String, value: Data)] = []
        var depth = 0
        var key: String?              // the member being read
        var valueStart = 0
        var pending: Range<Int>?      // a string at depth 1 where a key may be: a key if a ':' follows
        func finish(at end: Int) {
            if let key { members.append((key, Data(bytes[valueStart..<end]))) }
            key = nil
            pending = nil
        }
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                let start = i
                i = endOfString(bytes, from: i)
                pending = depth == 1 && key == nil ? start..<(i + 1) : nil
            case UInt8(ascii: ":"):
                if depth == 1, key == nil, let range = pending {
                    key = try? JSONDecoder().decode(String.self, from: Data(bytes[range]))
                    valueStart = i + 1
                }
                pending = nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if depth == 1 { finish(at: i) }
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 1 { finish(at: i) }
            default:
                break
            }
            i += 1
        }
        return members
    }

    /// Compact JSON laid out for reading with a two-space indent. Keys and numbers stay exactly as
    /// sent (JSONSerialization would reorder keys and print 0.3237 as 0.32369999999999999).
    static func pretty(_ json: Data) -> String {
        let bytes = [UInt8](json)
        var out: [UInt8] = []
        var depth = 0
        func newline() {
            out.append(UInt8(ascii: "\n"))
            out += repeatElement(UInt8(ascii: " "), count: max(0, 2 * depth))
        }
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            switch byte {
            case UInt8(ascii: "\""):
                let end = endOfString(bytes, from: i)
                out += bytes[i...end]
                i = end
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                out.append(byte)
                let close = byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                var next = i + 1
                while next < bytes.count, isWhitespace(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == close {   // `{}` and `[]` stay on one line
                    out.append(close)
                    i = next
                } else {
                    depth += 1
                    newline()
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                newline()
                out.append(byte)
            case UInt8(ascii: ","):
                out.append(byte)
                newline()
            case UInt8(ascii: ":"):
                out += [UInt8(ascii: ":"), UInt8(ascii: " ")]
            default:
                if !isWhitespace(byte) { out.append(byte) }
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The index of the quote that closes the string opening at `open`.
    private static func endOfString(_ bytes: [UInt8], from open: Int) -> Int {
        var i = open + 1
        while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
            i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
        }
        return min(i, bytes.count - 1)
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t")
    }
}
