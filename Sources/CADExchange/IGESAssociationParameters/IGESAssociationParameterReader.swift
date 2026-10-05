/// Separates standard tails only after proving the selected family's specified extent.
struct IGESAssociationParameterReader {
    struct Result {
        let parameters: [String]
        let associations: [Int]
        let properties: [Int]
    }
    func split(type: Int, form: Int, parameters p: [String],
               accounting: inout ExchangeResourceAccountant) throws -> Result {
        func integer(_ index: Int) throws -> Int {
            guard p.indices.contains(index), let n = Int(p[index]), n >= 0 else {
                throw ImportError.invalidData("Malformed IGES specified/tail count.")
            }
            return n
        }
        func sum(_ a: Int, _ b: Int) throws -> Int {
            let n = a.addingReportingOverflow(b)
            guard !n.overflow else { throw ImportError.invalidData("IGES parameter extent overflows.") }
            return n.partialValue
        }
        func times(_ a: Int, _ b: Int) throws -> Int {
            let n = a.multipliedReportingOverflow(by: b)
            guard !n.overflow else { throw ImportError.invalidData("IGES parameter extent overflows.") }
            return n.partialValue
        }
        let base: Int
        switch type {
        case 100: base = 8
        case 104: base = 12
        case 110: base = 7
        case 116: base = 5
        case 123: base = 4
        case 124: base = 13
        case 140, 142, 194, 198, 408: base = 6
        case 190: base = 4
        case 192, 196: base = 5
        case 308: base = try sum(4, integer(3))
        case 402 where [1, 7, 14, 15].contains(form): base = try sum(2, integer(1))
        case 126:
            let count = try sum(integer(1), 1), degree = try integer(2)
            base = try sum(13, sum(times(5, count), degree))
        case 128:
            let u = try sum(integer(1), 1), v = try sum(integer(2), 1)
            base = try sum(16, sum(sum(u, v), sum(sum(integer(3), integer(4)), times(4, times(u, v)))))
        case 186: base = try sum(4, times(2, integer(3)))
        case 502: base = try sum(2, times(3, integer(1)))
        case 504: base = try sum(2, times(5, integer(1)))
        case 510: base = try sum(4, integer(2))
        case 514: base = try sum(2, times(2, integer(1)))
        case 508:
            let count = try integer(1)
            guard count <= p.count / 5 else { throw ImportError.invalidData("Truncated IGES loop extent.") }
            var cursor = 2
            for _ in 0..<count {
                try accounting.recordIterations()
                let pairs = try integer(sum(cursor, 4))
                cursor = try sum(cursor, sum(5, times(2, pairs)))
                guard cursor <= p.count else { throw ImportError.invalidData("Truncated IGES loop pcurve extent.") }
            }
            base = cursor
        default: return .init(parameters: p, associations: [], properties: [])
        }
        guard base <= p.count else { throw ImportError.invalidData("Truncated IGES specified parameters.") }
        guard base < p.count else { return .init(parameters: p, associations: [], properties: []) }
        var cursor = base
        func pointers(_ cursor: inout Int, accounting: inout ExchangeResourceAccountant) throws -> [Int] {
            guard cursor < p.count else { return [] }
            let n = try integer(cursor)
            cursor = try sum(cursor, 1)
            guard n <= p.count - cursor else { throw ImportError.invalidData("Truncated IGES generic pointer list.") }
            let bytes = n.multipliedReportingOverflow(by: MemoryLayout<Int>.stride)
            guard !bytes.overflow else { throw ImportError.invalidData("IGES generic pointer storage overflows.") }
            try accounting.recordEntities(n); try accounting.recordIterations(n)
            try accounting.recordBytes(bytes.partialValue)
            var result: [Int] = []; result.reserveCapacity(n)
            for index in cursor..<(cursor + n) {
                let value = try integer(index)
                guard value > 0, value % 2 == 1 else { throw ImportError.invalidData("Malformed IGES generic directory pointer.") }
                result.append(value)
            }
            cursor += n
            return result
        }
        let associations = try pointers(&cursor, accounting: &accounting)
        let properties = try pointers(&cursor, accounting: &accounting)
        guard cursor == p.count else { throw ImportError.invalidData("Trailing IGES generic parameters.") }
        let bytes = base.multipliedReportingOverflow(by: MemoryLayout<String>.stride)
        guard !bytes.overflow else { throw ImportError.invalidData("IGES specified parameter storage overflows.") }
        try accounting.recordBytes(bytes.partialValue); try accounting.recordIterations(base)
        return .init(parameters: Array(p.prefix(base)), associations: associations, properties: properties)
    }
}
