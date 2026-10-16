import CADCore

/// Query-local finite Boolean compilation of original directed segment winding.
struct OriginalBoundaryBooleanCompiler {
    enum Node { case literal(Bool), sign(Int, OriginalPolynomialPredicate.Sign), not(Int), and(Int, Int), or(Int, Int) }
    struct Segment {
        let firstU: ExactRationalCoefficient, firstV: ExactRationalCoefficient
        let lastU: ExactRationalCoefficient, lastV: ExactRationalCoefficient
        let reference: OriginalNativeBoundaryDomain.SpanReference
    }
    var laws: [ExactIntersectionPolynomial] = []
    private var nodes: [Node] = []
    var boundaryNodes: [Int] = []
    var references: [OriginalNativeBoundaryDomain.SpanReference] = []

    mutating func node<A: ExactScalarAdmission & ~Copyable>(_ node: Node, usage: inout A) throws -> Int {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(1, of: Node.self, usage: &usage)
        let index = nodes.count; _ = try rationalAlgebraCount(index, 1)
        nodes.append(node); return index
    }
    mutating func conjunction<A: ExactScalarAdmission & ~Copyable>(_ a: Int, _ b: Int, usage: inout A) throws -> Int {
        if a == b { return a }
        if case .literal(let value) = nodes[a] { return value ? b : a }
        if case .literal(let value) = nodes[b] { return value ? a : b }
        return try node(.and(a, b), usage: &usage)
    }
    mutating func disjunction<A: ExactScalarAdmission & ~Copyable>(_ a: Int, _ b: Int, usage: inout A) throws -> Int {
        if a == b { return a }
        if case .literal(let value) = nodes[a] { return value ? a : b }
        if case .literal(let value) = nodes[b] { return value ? b : a }
        return try node(.or(a, b), usage: &usage)
    }
    mutating func negation<A: ExactScalarAdmission & ~Copyable>(_ a: Int, usage: inout A) throws -> Int {
        if case .literal(let value) = nodes[a] { return try node(.literal(!value), usage: &usage) }
        return try node(.not(a), usage: &usage)
    }
    mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: ExactIntersectionPolynomial, _ sign: OriginalPolynomialPredicate.Sign,
        usage: inout A) throws -> Int {
        for (index, original) in laws.enumerated() {
            try intersectionAlgebraStep(&usage)
            if try original.matches(law, usage: &usage) { return try node(.sign(index, sign), usage: &usage) }
        }
        try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
        let ordinal = laws.count; _ = try rationalAlgebraCount(ordinal, 1)
        laws.append(law); return try node(.sign(ordinal, sign), usage: &usage)
    }
    mutating func condition<A: ExactScalarAdmission & ~Copyable>(_ condition: OriginalIntersectionCellCondition,
        usage: inout A) throws -> Int {
        var result = try node(.literal(true), usage: &usage)
        for index in condition.polynomials.indices {
            try intersectionAlgebraStep(&usage)
            let sign: OriginalPolynomialPredicate.Sign
            switch condition.signs[index] { case .negative: sign = .negative; case .zero: sign = .zero; case .positive: sign = .positive }
            let value = try atom(condition.polynomials[index], sign, usage: &usage)
            result = try conjunction(result, value, usage: &usage)
        }
        return result
    }
    mutating func sourceSystem<A: ExactScalarAdmission & ~Copyable>(_ system: OriginalRationalIntersectionSystem, usage: inout A) throws -> Int {
        var result = try node(.literal(true), usage: &usage)
        for law in system.equations {
            try intersectionAlgebraStep(&usage)
            let zero = try atom(law, .zero, usage: &usage)
            result = try conjunction(result, zero, usage: &usage)
        }
        for law in system.denominatorGuards {
            try intersectionAlgebraStep(&usage)
            let zero = try atom(law, .zero, usage: &usage)
            let nonzero = try negation(zero, usage: &usage)
            result = try conjunction(result, nonzero, usage: &usage)
        }
        return result
    }
    mutating func boundary<A: ExactScalarAdmission & ~Copyable>(_ domain: OriginalNativeBoundaryDomain,
        selection: OriginalNativeBoundaryDomain.Selection, usage: inout A) throws -> Int {
        let count = domain.source.variableCount, axis = domain.source.uAxis
        let u = try ExactIntersectionPolynomial.coordinate(variableCount: count, at: axis, usage: &usage)
        let v = try ExactIntersectionPolynomial.coordinate(variableCount: count, at: axis + 1, usage: &usage)
        var outer = try node(.literal(false), usage: &usage)
        var inner = try node(.literal(false), usage: &usage)
        var anyBoundary = try node(.literal(false), usage: &usage)
        for (ordinal, loop) in domain.loops.enumerated() {
            try intersectionAlgebraStep(&usage)
            let segments = try Self.segments(loop, ordinal: ordinal, source: domain.source, usage: &usage)
            var crossings: [(node: Int, delta: Int)] = []
            try RationalAlgebraStorage.retain(segments.count, of: (Int, Int).self, usage: &usage)
            var loopBoundary = try node(.literal(false), usage: &usage)
            for segment in segments {
                try intersectionAlgebraStep(&usage)
                let du = try segment.lastU.subtracting(segment.firstU, usage: &usage)
                let dv = try segment.lastV.subtracting(segment.firstV, usage: &usage)
                let x = try u.subtracting(.constant(variableCount: count, value: segment.firstU, usage: &usage), usage: &usage)
                let y = try v.subtracting(.constant(variableCount: count, value: segment.firstV, usage: &usage), usage: &usage)
                let cross = try y.scaled(by: du, usage: &usage).subtracting(x.scaled(by: dv, usage: &usage), usage: &usage)
                let coordinate = du.isZero ? v : u
                let start = du.isZero ? segment.firstV : segment.firstU
                let end = du.isZero ? segment.lastV : segment.lastU
                let ascending = !(try end.subtracting(start, usage: &usage)).isNegative
                let lower = try coordinate.subtracting(.constant(variableCount: count, value: ascending ? start : end, usage: &usage), usage: &usage)
                let upper = try coordinate.subtracting(.constant(variableCount: count, value: ascending ? end : start, usage: &usage), usage: &usage)
                let onLine = try atom(cross, .zero, usage: &usage)
                let above = try negation(atom(lower, .negative, usage: &usage), usage: &usage)
                let below = try negation(atom(upper, .positive, usage: &usage), usage: &usage)
                let onSegment = try conjunction(conjunction(onLine, above, usage: &usage), below, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalNativeBoundaryDomain.SpanReference.self, usage: &usage)
                boundaryNodes.append(onSegment); references.append(segment.reference)
                loopBoundary = try disjunction(loopBoundary, onSegment, usage: &usage)
                if !dv.isZero {
                    let first = try v.subtracting(.constant(variableCount: count, value: dv.isPositive ? segment.firstV : segment.lastV, usage: &usage), usage: &usage)
                    let last = try v.subtracting(.constant(variableCount: count, value: dv.isPositive ? segment.lastV : segment.firstV, usage: &usage), usage: &usage)
                    let low = try negation(atom(first, .negative, usage: &usage), usage: &usage)
                    let high = try atom(last, .negative, usage: &usage)
                    let side = try atom(cross, dv.isPositive ? .positive : .negative, usage: &usage)
                    crossings.append((try conjunction(conjunction(low, high, usage: &usage), side, usage: &usage), dv.isPositive ? 1 : -1))
                }
            }
            let winding = try nonzeroWinding(crossings, usage: &usage)
            anyBoundary = try disjunction(anyBoundary, loopBoundary, usage: &usage)
            if loop.isInner {
                let strict = try conjunction(winding, negation(loopBoundary, usage: &usage), usage: &usage)
                inner = try disjunction(inner, strict, usage: &usage)
            } else {
                outer = try disjunction(outer, disjunction(winding, loopBoundary, usage: &usage), usage: &usage)
            }
        }
        let closed = try conjunction(outer, negation(inner, usage: &usage), usage: &usage)
        switch selection {
        case .closed: return closed
        case .strictInterior: return try conjunction(closed, negation(anyBoundary, usage: &usage), usage: &usage)
        case .boundary: return try conjunction(closed, anyBoundary, usage: &usage)
        }
    }
    private mutating func nonzeroWinding<A: ExactScalarAdmission & ~Copyable>(_ crossings: [(node: Int, delta: Int)],
        usage: inout A) throws -> Int {
        let count = crossings.count
        let capacity = try rationalAlgebraCount(try rationalAlgebraCount(count, 2, multiply: true), 1)
        try RationalAlgebraStorage.retain(capacity, of: Int.self, usage: &usage)
        var next: [Int] = []; next.reserveCapacity(capacity)
        for sum in -count...count {
            try intersectionAlgebraStep(&usage)
            next.append(try node(.literal(sum != 0), usage: &usage))
        }
        if count == 0 { return next[0] }
        for index in crossings.indices.reversed() {
            try intersectionAlgebraStep(&usage)
            let size = try rationalAlgebraCount(try rationalAlgebraCount(index, 2, multiply: true), 1)
            try RationalAlgebraStorage.retain(size, of: Int.self, usage: &usage)
            var current: [Int] = []; current.reserveCapacity(size)
            let crossing = crossings[index], inverse = try negation(crossing.node, usage: &usage)
            for sum in -index...index {
            try intersectionAlgebraStep(&usage)
                let offset = index + 1
                let yes = next[sum + crossing.delta + offset], no = next[sum + offset]
                let selected = try conjunction(crossing.node, yes, usage: &usage)
                let absent = try conjunction(inverse, no, usage: &usage)
                current.append(try disjunction(selected, absent, usage: &usage))
            }
            next = current
        }
        return next[0]
    }
    func values<A: ExactScalarAdmission & ~Copyable>(signs: [OriginalPolynomialPredicate.Sign], usage: inout A) throws -> [Bool] {
        guard signs.count == laws.count else { throw rationalAlgebraFailure("Boundary selection lost its complete original law binding.") }
        try RationalAlgebraStorage.retain(nodes.count, of: Bool.self, usage: &usage)
        var values: [Bool] = []; values.reserveCapacity(nodes.count)
        for node in nodes {
            try intersectionAlgebraStep(&usage)
            let value: Bool
            switch node {
            case .literal(let original): value = original
            case .sign(let index, let sign): value = signs[index] == sign
            case .not(let child): value = !values[child]
            case .and(let a, let b): value = values[a] && values[b]
            case .or(let a, let b): value = values[a] || values[b]
            }
            values.append(value)
        }
        return values
    }
    func instructions<A: ExactScalarAdmission & ~Copyable>(_ root: Int, usage: inout A) throws -> [OriginalPolynomialPredicate.Instruction] {
        let capacity = try rationalAlgebraCount(nodes.count, 3, multiply: true)
        try RationalAlgebraStorage.retain(capacity, of: (Int, Bool).self, usage: &usage)
        var pending: [(index: Int, finished: Bool)] = [(root, false)]; pending.reserveCapacity(capacity)
        var result: [OriginalPolynomialPredicate.Instruction] = []
        while let item = pending.popLast() {
            try intersectionAlgebraStep(&usage)
            let instruction: OriginalPolynomialPredicate.Instruction?
            switch nodes[item.index] {
            case .literal(let value): instruction = .literal(value)
            case .sign(let index, let sign): instruction = .sign(polynomial: index, sign)
            case .not(let child):
                if item.finished { instruction = .not }
                else { pending.append((item.index, true)); pending.append((child, false)); instruction = nil }
            case .and(let a, let b), .or(let a, let b):
                if item.finished {
                    if case .and = nodes[item.index] { instruction = .and } else { instruction = .or }
                } else {
                    pending.append((item.index, true)); pending.append((b, false)); pending.append((a, false)); instruction = nil
                }
            }
            guard pending.count <= capacity else { throw rationalAlgebraFailure("Boundary Boolean traversal exceeded its checked node cover.") }
            if let instruction {
                try RationalAlgebraStorage.retain(1, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
                _ = try rationalAlgebraCount(result.count, 1); result.append(instruction)
            }
        }
        return result
    }
    private static func segments<A: ExactScalarAdmission & ~Copyable>(_ loop: OriginalNativeBoundaryDomain.Loop, ordinal: Int,
        source: OriginalNativeBoundaryDomain.Source, usage: inout A) throws -> [Segment] {
        var result: [Segment] = []
        func point(_ u: Double, _ v: Double) throws -> (ExactRationalCoefficient, ExactRationalCoefficient) {
            (try .originalDouble(u, usage: &usage), try .originalDouble(v, usage: &usage))
        }
        func append(_ first: (ExactRationalCoefficient, ExactRationalCoefficient),
            _ last: (ExactRationalCoefficient, ExactRationalCoefficient), curve: Int, segment: Int) throws {
            try intersectionAlgebraStep(&usage)
            guard try !last.0.subtracting(first.0, usage: &usage).isZero ||
                !last.1.subtracting(first.1, usage: &usage).isZero else {
                throw GeometryConversionError.invalidInput("An original boundary contains a degenerate directed segment.")
            }
            if let previous = result.last {
                guard try previous.lastU.subtracting(first.0, usage: &usage).isZero,
                    try previous.lastV.subtracting(first.1, usage: &usage).isZero else {
                    throw GeometryConversionError.invalidInput("Original directed pcurves do not form an exact closed chain.")
                }
            }
            try RationalAlgebraStorage.retain(1, of: Segment.self, usage: &usage)
            result.append(.init(firstU: first.0, firstV: first.1, lastU: last.0, lastV: last.1,
                reference: .init(loopOrdinal: ordinal, curveOrdinal: curve, segmentOrdinal: segment)))
        }
        for (index, curve) in loop.curves.enumerated() {
            try intersectionAlgebraStep(&usage)
            switch curve {
            case .constantU(let u, let start, let end): try append(point(u, start), point(u, end), curve: index, segment: 0)
            case .constantV(let v, let start, let end): try append(point(start, v), point(end, v), curve: index, segment: 0)
            case .affine(let origin, let direction, let start, let end):
                let o = try point(origin.x, origin.y), d = try point(direction.x, direction.y)
                let a = try ExactRationalCoefficient.originalDouble(start, usage: &usage)
                let b = try ExactRationalCoefficient.originalDouble(end, usage: &usage)
                try append((o.0.adding(d.0.multiplied(by: a, usage: &usage), usage: &usage),
                    o.1.adding(d.1.multiplied(by: a, usage: &usage), usage: &usage)),
                    (o.0.adding(d.0.multiplied(by: b, usage: &usage), usage: &usage),
                    o.1.adding(d.1.multiplied(by: b, usage: &usage), usage: &usage)), curve: index, segment: 0)
            case .polyline(let points):
                guard points.count >= 2 else { throw GeometryConversionError.invalidInput("Original boundary polyline has no source segment.") }
                for segment in 0..<(points.count - 1) {
                    try append(point(points[segment].u, points[segment].v), point(points[segment + 1].u, points[segment + 1].v),
                        curve: index, segment: segment)
                }
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Rational/implicit/nonrational pcurve families
                // need their original complete chart and winding compiler. The public face clipping
                // route must fail until those original laws and all boundary coincidences are proved.
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                    tolerance: OriginalNativeBoundaryDomain.tolerance(source),
                    message: "Original face clipping has no complete boundary compiler for this pcurve family.")
            }
        }
        guard let first = result.first, let last = result.last,
            try first.firstU.subtracting(last.lastU, usage: &usage).isZero,
            try first.firstV.subtracting(last.lastV, usage: &usage).isZero else {
            throw GeometryConversionError.invalidInput("Original boundary loop is not exactly closed.")
        }
        return result
    }
}
