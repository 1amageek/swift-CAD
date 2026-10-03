import Foundation
import CADCore

struct STEPAssemblySyntax: STEPFieldReading {
    let entities: [Int: String]
    func entity(_ id: Int) throws -> String {
        guard let value = entities[id] else { throw ImportError.missingRequiredEntity("STEP assembly #\(id)") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func name(_ id: Int) throws -> String {
        let e = try entity(id)
        if e.first == "(" { return "" }
        guard let p = e.firstIndex(of: "(") else { throw ImportError.invalidData("Malformed STEP assembly entity.") }
        return String(e[..<p]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    func arguments(_ id: Int, component: String? = nil) throws -> [String] {
        let e = try entity(id).unicodeScalars
        let start: String.Index
        if let component {
            // Lexical component matching excludes names contained inside STEP quoted strings.
            var cursor = e.startIndex
            var quoted = false
            var found: String.Index?
            while cursor < e.endIndex {
                if e[cursor] == "'" {
                    let next = e.index(after: cursor)
                    if quoted, next < e.endIndex, e[next] == "'" { cursor = e.index(after: next); continue }
                    quoted.toggle()
                }
                if !quoted, e[cursor...].starts(with: (component + "(").unicodeScalars) {
                    let preceding = cursor == e.startIndex ? "(" : e[e.index(before: cursor)]
                    if preceding == "(" || preceding.properties.isWhitespace { found = e.index(cursor, offsetBy: component.unicodeScalars.count); break }
                }
                cursor = e.index(after: cursor)
            }
            guard let found else { throw ImportError.invalidData("Missing STEP component \(component).") }
            start = found
        } else {
            guard let opening = e.firstIndex(of: "("), e.first != "(" else {
                throw ImportError.invalidData("Expected a simple STEP assembly entity.")
            }
            start = opening
        }
        var cursor = e.index(after: start), depth = 1, quoted = false
        let content = cursor
        while cursor < e.endIndex {
            let ch = e[cursor]
            if ch == "'" {
                let next = e.index(after: cursor)
                if quoted, next < e.endIndex, e[next] == "'" { cursor = e.index(after: next); continue }
                quoted.toggle()
            } else if !quoted {
                if ch == "(" { depth += 1 }
                if ch == ")" { depth -= 1; if depth == 0 { return try split(String(e[content..<cursor])) } }
            }
            cursor = e.index(after: cursor)
        }
        throw ImportError.invalidData("Unterminated STEP assembly component.")
    }
    func split(_ value: String) throws -> [String] {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let scalars = value.unicodeScalars
        var result: [String] = [], depth = 0, quoted = false
        var start = scalars.startIndex, cursor = start
        while cursor < scalars.endIndex {
            let ch = scalars[cursor]
            if ch == "'" {
                let next = scalars.index(after: cursor)
                if quoted, next < scalars.endIndex, scalars[next] == "'" { cursor = scalars.index(after: next); continue }
                quoted.toggle()
            } else if !quoted {
                if ch == "(" { depth += 1 }; if ch == ")" { depth -= 1 }
                if ch == ",", depth == 0 {
                    result.append(String(scalars[start..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = scalars.index(after: cursor)
                }
            }
            guard depth >= 0 else { throw ImportError.invalidData("Malformed STEP tuple.") }
            cursor = scalars.index(after: cursor)
        }
        guard depth == 0, !quoted else { throw ImportError.invalidData("Malformed STEP tuple/string.") }
        result.append(String(scalars[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        guard result.allSatisfy({ !$0.isEmpty }) else { throw ImportError.invalidData("Empty STEP argument.") }
        return result
    }
    func reference(_ value: String) throws -> Int {
        guard value.first == "#", let id = Int(value.dropFirst()), id > 0 else {
            throw ImportError.invalidData("Malformed STEP reference.")
        }
        return id
    }
    func list(_ value: String) throws -> [Int] {
        guard value.first == "(", value.last == ")" else { throw ImportError.invalidData("Malformed STEP reference list.") }
        return try split(String(value.dropFirst().dropLast())).map(reference)
    }
    func string(_ value: String) throws -> String {
        try decodedString(value, limits: .standard).value
    }
    func decodedString(_ value: String, limits: STEPStringLimits) throws -> STEPStringResult {
        try STEPStringCodec().decode(value, limits: limits)
    }
    func numbers(_ value: String) throws -> [Double] {
        guard value.first == "(", value.last == ")" else { throw ImportError.invalidData("Expected STEP numeric tuple.") }
        return try split(String(value.dropFirst().dropLast())).map {
            guard let number = Double($0), number.isFinite else { throw ImportError.invalidData("Nonfinite STEP number.") }
            return number
        }
    }
}
