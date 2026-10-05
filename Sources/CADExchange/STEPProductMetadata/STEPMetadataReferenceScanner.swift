import CADIR

/// Parses reference tokens outside STEP strings; reference text within labels is never topology.
enum STEPMetadataReferenceScanner {
    static func references(in token: String) throws -> [Int] {
        var result: [Int] = []
        try visitReferences(in: token) { result.append($0) }
        return result
    }

    static func visitReferences(in token: String, visit: (Int) throws -> Void) throws {
        var index = token.startIndex, quoted = false
        while index < token.endIndex {
            let c = token[index]
            if c == "'" {
                let next = token.index(after: index)
                if quoted, next < token.endIndex, token[next] == "'" { index = token.index(after: next); continue }
                quoted.toggle()
            } else if !quoted, c == "#" {
                var end = token.index(after: index)
                while end < token.endIndex, token[end].isNumber { end = token.index(after: end) }
                guard let value = Int(token[token.index(after: index)..<end]), value > 0 else {
                    throw ProductAttributeError.invalidSource("Malformed STEP metadata reference.")
                }
                try visit(value); index = end; continue
            }
            index = token.index(after: index)
        }
        guard !quoted else { throw ProductAttributeError.invalidSource("Unterminated STEP metadata reference field string.") }
    }
}
