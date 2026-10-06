import CADCore

/// Original rational polynomial with inline coordinates for source laws and quantified incidence.
package struct ExactIntersectionPolynomial: Equatable, Sendable {
    package static let maximumVariableCount = 9
    package struct Power: Hashable, Sendable {
        let a: Int, b: Int, c: Int, d: Int, e: Int
        let f: Int, g: Int, h: Int, i: Int
        var values: (Int, Int, Int, Int, Int, Int, Int, Int, Int) { (a, b, c, d, e, f, g, h, i) }

        init(_ values: (Int, Int, Int, Int, Int), variableCount: Int) throws {
            try self.init((values.0, values.1, values.2, values.3, values.4, 0, 0, 0, 0), variableCount: variableCount)
        }
        init(_ values: (Int, Int, Int, Int, Int, Int, Int, Int, Int), variableCount: Int) throws {
            guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount) else {
                throw rationalAlgebraFailure("Intersection powers require the admitted polynomial ring.")
            }
            a = values.0; b = values.1; c = values.2; d = values.3; e = values.4
            f = values.5; g = values.6; h = values.7; i = values.8
            for coordinate in 0..<ExactIntersectionPolynomial.maximumVariableCount {
                let exponent = try exponent(at: coordinate)
                guard exponent >= 0, coordinate < variableCount || exponent == 0 else {
                    throw rationalAlgebraFailure("Intersection powers do not belong to the original polynomial ring.")
                }
            }
        }
        func exponent(at coordinate: Int) throws -> Int {
            switch coordinate {
            case 0: return a
            case 1: return b
            case 2: return c
            case 3: return d
            case 4: return e
            case 5: return f
            case 6: return g
            case 7: return h
            case 8: return i
            default: throw rationalAlgebraFailure("Intersection polynomial coordinate is outside its ring.")
            }
        }
        func precedes(_ other: Self) -> Bool {
            if i != other.i { return i < other.i }
            if h != other.h { return h < other.h }
            if g != other.g { return g < other.g }
            if f != other.f { return f < other.f }
            if e != other.e { return e < other.e }
            if d != other.d { return d < other.d }
            if c != other.c { return c < other.c }
            if b != other.b { return b < other.b }
            return a < other.a
        }
        func divides(_ other: Self) -> Bool {
            a <= other.a && b <= other.b && c <= other.c && d <= other.d && e <= other.e &&
            f <= other.f && g <= other.g && h <= other.h && i <= other.i
        }
        func sum(_ other: Self, variableCount: Int) throws -> Self {
            try Self((rationalAlgebraCount(a, other.a), rationalAlgebraCount(b, other.b),
                rationalAlgebraCount(c, other.c), rationalAlgebraCount(d, other.d), rationalAlgebraCount(e, other.e),
                rationalAlgebraCount(f, other.f), rationalAlgebraCount(g, other.g), rationalAlgebraCount(h, other.h),
                rationalAlgebraCount(i, other.i)), variableCount: variableCount)
        }
        func quotient(by other: Self, variableCount: Int) throws -> Self {
            guard other.divides(self) else { throw rationalAlgebraFailure("Original monomial quotient has a negative exponent.") }
            return try Self((a-other.a, b-other.b, c-other.c, d-other.d, e-other.e,
                f-other.f, g-other.g, h-other.h, i-other.i), variableCount: variableCount)
        }
        func leastCommonMultiple(_ other: Self, variableCount: Int) throws -> Self {
            try Self((max(a,other.a), max(b,other.b), max(c,other.c), max(d,other.d), max(e,other.e),
                max(f,other.f), max(g,other.g), max(h,other.h), max(i,other.i)), variableCount: variableCount)
        }
        func removing(_ coordinate: Int, variableCount: Int) throws -> Self {
            try Self((coordinate == 0 ? 0 : a, coordinate == 1 ? 0 : b, coordinate == 2 ? 0 : c,
                coordinate == 3 ? 0 : d, coordinate == 4 ? 0 : e, coordinate == 5 ? 0 : f,
                coordinate == 6 ? 0 : g, coordinate == 7 ? 0 : h, coordinate == 8 ? 0 : i), variableCount: variableCount)
        }
    }

    package let variableCount: Int
    private let coefficients: [Power: ExactRationalCoefficient]

    private init(variableCount: Int, coefficients: [Power: ExactRationalCoefficient]) {
        self.variableCount = variableCount
        self.coefficients = coefficients
    }

    package var isZero: Bool { coefficients.isEmpty }
    /// Equality needs no ordered temporary table; admit the immutable traversal.
    package func matches<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Bool {
        try requireSameRing(other)
        try intersectionAlgebraStep(&usage)
        try usage.consumeExactWork(rationalAlgebraCount(coefficients.count, other.coefficients.count))
        return coefficients == other.coefficients
    }
    package var isConstant: Bool {
        if coefficients.isEmpty { return true }
        guard coefficients.count == 1, let power = coefficients.first?.key else { return false }
        return power.a == 0 && power.b == 0 && power.c == 0 && power.d == 0 && power.e == 0 && power.f == 0 && power.g == 0 && power.h == 0 && power.i == 0
    }
    func leading<B: RationalAlgebraAdmitting>(usage: inout B)
        throws -> (power: Power, coefficient: ExactRationalCoefficient)? {
        var result: (power: Power, coefficient: ExactRationalCoefficient)?
        for (power, coefficient) in coefficients {
            try intersectionAlgebraStep(&usage)
            if let previous = result {
                if previous.power.precedes(power) { result = (power, coefficient) }
            } else { result = (power, coefficient) }
        }
        return result
    }

    package static func zero(variableCount: Int) throws -> Self {
        guard (1...Self.maximumVariableCount).contains(variableCount) else {
            throw rationalAlgebraFailure("Intersection polynomial ring requires one through nine coordinates.")
        }
        return Self(variableCount: variableCount, coefficients: [:])
    }

    package static func monomial<B: RationalAlgebraAdmitting>(variableCount: Int,
        powers: (Int, Int, Int, Int, Int), coefficient: ExactRationalCoefficient,
        usage: inout B) throws -> Self {
        return try monomial(variableCount: variableCount,
            powers: (powers.0, powers.1, powers.2, powers.3, powers.4, 0, 0, 0, 0), coefficient: coefficient, usage: &usage)
    }

    package static func monomial<B: RationalAlgebraAdmitting>(variableCount: Int,
        powers: (Int, Int, Int, Int, Int, Int, Int, Int, Int), coefficient: ExactRationalCoefficient,
        usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        let power = try Power(powers, variableCount: variableCount)
        if coefficient.isZero { return try .zero(variableCount: variableCount) }
        try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        return Self(variableCount: variableCount, coefficients: [power: coefficient])
    }

    package static func constant<B: RationalAlgebraAdmitting>(variableCount: Int,
        value: ExactRationalCoefficient, usage: inout B) throws -> Self {
        try monomial(variableCount: variableCount, powers: (0, 0, 0, 0, 0),
                     coefficient: value, usage: &usage)
    }

    package static func coordinate<B: RationalAlgebraAdmitting>(variableCount: Int,
        at coordinate: Int, usage: inout B) throws -> Self {
        guard coordinate >= 0, coordinate < variableCount else {
            throw rationalAlgebraFailure("Original intersection coordinate does not belong to its ring.")
        }
        return try monomial(variableCount: variableCount,
            powers: (coordinate == 0 ? 1 : 0, coordinate == 1 ? 1 : 0,
                     coordinate == 2 ? 1 : 0, coordinate == 3 ? 1 : 0,
                     coordinate == 4 ? 1 : 0, coordinate == 5 ? 1 : 0, coordinate == 6 ? 1 : 0,
                     coordinate == 7 ? 1 : 0, coordinate == 8 ? 1 : 0), coefficient: .one, usage: &usage)
    }

    package static func embedding<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        variableCount: Int, uCoordinate: Int, vCoordinate: Int, usage: inout B) throws -> Self {
        guard uCoordinate >= 0, vCoordinate >= 0, uCoordinate < variableCount,
              vCoordinate < variableCount, uCoordinate != vCoordinate else {
            throw rationalAlgebraFailure("Original native variables require distinct intersection coordinates.")
        }
        var result = try Self.zero(variableCount: variableCount)
        for (power, coefficient) in try source.orderedTerms(usage: &usage) {
            let term = try monomial(variableCount: variableCount,
                powers: (uCoordinate == 0 ? power.u : vCoordinate == 0 ? power.v : 0,
                         uCoordinate == 1 ? power.u : vCoordinate == 1 ? power.v : 0,
                         uCoordinate == 2 ? power.u : vCoordinate == 2 ? power.v : 0,
                         uCoordinate == 3 ? power.u : vCoordinate == 3 ? power.v : 0,
                         uCoordinate == 4 ? power.u : vCoordinate == 4 ? power.v : 0,
                         uCoordinate == 5 ? power.u : vCoordinate == 5 ? power.v : 0,
                         uCoordinate == 6 ? power.u : vCoordinate == 6 ? power.v : 0,
                         uCoordinate == 7 ? power.u : vCoordinate == 7 ? power.v : 0,
                         uCoordinate == 8 ? power.u : vCoordinate == 8 ? power.v : 0),
                coefficient: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    /// Removes only proved-unused suffix slots after exact projection.
    package func lowered<B: RationalAlgebraAdmitting>(to count: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard count >= 1, count <= variableCount else {
            throw rationalAlgebraFailure("Projected ring reduction requires a retained nonempty coordinate prefix.")
        }
        for term in try orderedTerms(usage: &usage) {
            for axis in count..<variableCount {
                try intersectionAlgebraStep(&usage)
                guard try term.key.exponent(at: axis) == 0 else {
                    throw rationalAlgebraFailure("Projected ring reduction cannot discard an original active coordinate.")
                }
            }
        }
        return Self(variableCount: count, coefficients: coefficients)
    }

    /// Injective coordinate renaming preserves original coefficients and source monomials.
    package func remapped<B: RationalAlgebraAdmitting>(to count: Int, coordinates: [Int], usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard (1...Self.maximumVariableCount).contains(count), coordinates.count == variableCount else {
            throw rationalAlgebraFailure("Original remapping requires every source coordinate and an admitted target ring.")
        }
        for index in coordinates.indices {
            guard coordinates[index] >= 0, coordinates[index] < count else {
                throw rationalAlgebraFailure("Original remapping has a coordinate outside the target ring.")
            }
            for previous in 0..<index {
                try intersectionAlgebraStep(&usage)
                guard coordinates[previous] != coordinates[index] else {
                    throw rationalAlgebraFailure("Original coordinate remapping must be injective.")
                }
            }
        }
        var result = try Self.zero(variableCount: count)
        for term in try orderedTerms(usage: &usage) {
            var values = (0, 0, 0, 0, 0, 0, 0, 0, 0)
            for coordinate in coordinates.indices {
                try intersectionAlgebraStep(&usage)
                let exponent = try term.key.exponent(at: coordinate)
                switch coordinates[coordinate] {
                case 0: values.0 = exponent
                case 1: values.1 = exponent
                case 2: values.2 = exponent
                case 3: values.3 = exponent
                case 4: values.4 = exponent
                case 5: values.5 = exponent
                case 6: values.6 = exponent
                case 7: values.7 = exponent
                case 8: values.8 = exponent
                default: throw rationalAlgebraFailure("Admitted remapping lost its target coordinate.")
                }
            }
            result = try result.adding(Self.monomial(variableCount: count, powers: values,
                coefficient: term.value, usage: &usage), usage: &usage)
        }
        return result
    }

    package func lifted<B: RationalAlgebraAdmitting>(to count: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard count >= variableCount, count <= Self.maximumVariableCount else {
            throw rationalAlgebraFailure("Original polynomial lifting cannot remove coordinates.")
        }
        return Self(variableCount: count, coefficients: coefficients)
    }

    func orderedTerms<B: RationalAlgebraAdmitting>(usage: inout B)
        throws -> [(key: Power, value: ExactRationalCoefficient)] {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (Power, ExactRationalCoefficient).self, usage: &usage)
        let levels = coefficients.count <= 1 ? 0 : Int.bitWidth - (coefficients.count - 1).leadingZeroBitCount
        try usage.consumeExactWork(rationalAlgebraCount(coefficients.count, levels + 1, multiply: true))
        return coefficients.sorted { $1.key.precedes($0.key) }
    }

    package func adding<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try requireSameRing(other)
        try intersectionAlgebraStep(&usage)
        if isZero { return other }
        if other.isZero { return self }
        try RationalAlgebraStorage.retain(rationalAlgebraCount(coefficients.count, other.coefficients.count),
            of: (Power, ExactRationalCoefficient).self, usage: &usage)
        // A new polynomial owns its coefficient table; COW detachment is admitted above.
        var result = coefficients
        for (power, value) in try other.orderedTerms(usage: &usage) {
            try intersectionAlgebraStep(&usage)
            let sum = try (result[power] ?? .zero).adding(value, usage: &usage)
            if sum.isZero { result.removeValue(forKey: power) } else { result[power] = sum }
        }
        return Self(variableCount: variableCount, coefficients: result)
    }

    package func scaled<B: RationalAlgebraAdmitting>(by scale: ExactRationalCoefficient,
        usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        if scale.isZero { return try .zero(variableCount: variableCount) }
        if scale == .one { return self }
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var result: [Power: ExactRationalCoefficient] = [:]
        for (power, value) in try orderedTerms(usage: &usage) {
            try intersectionAlgebraStep(&usage)
            let coefficient = try value.multiplied(by: scale, usage: &usage)
            if !coefficient.isZero { result[power] = coefficient }
        }
        return Self(variableCount: variableCount, coefficients: result)
    }

    package func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try adding(other.scaled(by: .one.negated, usage: &usage), usage: &usage)
    }

    package func multiplied<B: RationalAlgebraAdmitting>(by other: Self,
        usage: inout B) throws -> Self {
        try requireSameRing(other)
        try intersectionAlgebraStep(&usage)
        if isZero || other.isZero { return try .zero(variableCount: variableCount) }
        if isConstant, let value = coefficients.first?.value { return try other.scaled(by: value, usage: &usage) }
        if other.isConstant, let value = other.coefficients.first?.value { return try scaled(by: value, usage: &usage) }
        var result: [Power: ExactRationalCoefficient] = [:]
        let rhs = try other.orderedTerms(usage: &usage)
        for (a, x) in try orderedTerms(usage: &usage) {
            for (b, y) in rhs {
                try intersectionAlgebraStep(&usage)
                let power = try a.sum(b, variableCount: variableCount)
                let value = try (result[power] ?? .zero).adding(x.multiplied(by: y, usage: &usage), usage: &usage)
                if value.isZero { result.removeValue(forKey: power) }
                else {
                    if result[power] == nil {
                        try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
                    }
                    result[power] = value
                }
            }
        }
        return Self(variableCount: variableCount, coefficients: result)
    }

    package func differentiated<B: RationalAlgebraAdmitting>(at coordinate: Int,
        usage: inout B) throws -> Self {
        guard coordinate >= 0, coordinate < variableCount else {
            throw rationalAlgebraFailure("Original derivative coordinate is outside the intersection ring.")
        }
        let unit = try Self.coordinate(variableCount: variableCount, at: coordinate, usage: &usage)
        guard let unitPower = try unit.leading(usage: &usage)?.power else {
            throw rationalAlgebraFailure("Original coordinate polynomial lost its monomial.")
        }
        var result = try Self.zero(variableCount: variableCount)
        for (power, value) in try orderedTerms(usage: &usage) {
            let exponent = try power.exponent(at: coordinate)
            if exponent == 0 { continue }
            let reduced = try power.quotient(by: unitPower, variableCount: variableCount)
            let coefficient = try value.multiplied(by: .natural(exponent, usage: &usage), usage: &usage)
            let term = try Self.monomial(variableCount: variableCount,
                powers: reduced.values,
                coefficient: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    package func evaluated<B: RationalAlgebraAdmitting>(at coordinates: [ExactRationalCoefficient],
        usage: inout B) throws -> ExactRationalCoefficient {
        guard coordinates.count == variableCount else {
            throw rationalAlgebraFailure("Intersection evaluation requires every original coordinate.")
        }
        var result = ExactRationalCoefficient.zero
        for (power, coefficient) in try orderedTerms(usage: &usage) {
            var term = coefficient
            for index in coordinates.indices {
                var exponent = try power.exponent(at: index), factor = coordinates[index]
                while exponent > 0 {
                    try intersectionAlgebraStep(&usage)
                    if exponent & 1 != 0 { term = try term.multiplied(by: factor, usage: &usage) }
                    exponent /= 2
                    if exponent > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
                }
            }
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    func monic<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        guard let lead = try leading(usage: &usage) else { return self }
        if lead.coefficient == .one { return self }
        return try scaled(by: .one.divided(by: lead.coefficient, usage: &usage), usage: &usage)
    }

    package func axisCoefficients<B: RationalAlgebraAdmitting>(at axis: Int,
        usage: inout B) throws -> [Self] {
        guard axis >= 0, axis < variableCount else {
            throw rationalAlgebraFailure("Projection axis does not belong to the original ring.")
        }
        let terms = try orderedTerms(usage: &usage)
        var degree = -1
        for term in terms {
            try intersectionAlgebraStep(&usage)
            degree = max(degree, try term.key.exponent(at: axis))
        }
        if degree < 0 { return [] }
        let count = try rationalAlgebraCount(degree, 1)
        try RationalAlgebraStorage.retain(count, of: Self.self, usage: &usage)
        var result = Array(repeating: try Self.zero(variableCount: variableCount), count: count)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            let power = term.key
            let exponent = try power.exponent(at: axis)
            let coefficient = try Self.monomial(variableCount: variableCount,
                powers: try power.removing(axis, variableCount: variableCount).values, coefficient: term.value, usage: &usage)
            result[exponent] = try result[exponent].adding(coefficient, usage: &usage)
        }
        return result
    }

    package func dividedExactly<B: RationalAlgebraAdmitting>(by divisor: Self,
        usage: inout B) throws -> Self {
        try requireSameRing(divisor)
        guard let denominator = try divisor.leading(usage: &usage) else {
            throw rationalAlgebraFailure("Exact intersection polynomial division has a zero divisor.")
        }
        if divisor.isConstant {
            return try scaled(by: .one.divided(by: denominator.coefficient, usage: &usage), usage: &usage)
        }
        var pending = self
        var quotient = try Self.zero(variableCount: variableCount)
        while let lead = try pending.leading(usage: &usage) {
            try intersectionAlgebraStep(&usage)
            guard denominator.power.divides(lead.power) else {
                throw rationalAlgebraFailure("Exact intersection polynomial division has a nonzero remainder.")
            }
            let power = try lead.power.quotient(by: denominator.power, variableCount: variableCount)
            let term = try Self.monomial(variableCount: variableCount,
                powers: power.values,
                coefficient: lead.coefficient.divided(by: denominator.coefficient, usage: &usage),
                usage: &usage)
            pending = try pending.subtracting(term.multiplied(by: divisor, usage: &usage), usage: &usage)
            if let next = try pending.leading(usage: &usage), !next.power.precedes(lead.power) {
                throw rationalAlgebraFailure("Exact polynomial division did not decrease its leading monomial.")
            }
            quotient = try quotient.adding(term, usage: &usage)
        }
        return quotient
    }

    private func requireSameRing(_ other: Self) throws {
        guard variableCount == other.variableCount else {
            throw rationalAlgebraFailure("Intersection arithmetic cannot mix original parameter rings.")
        }
    }
}

func intersectionAlgebraStep<B: RationalAlgebraAdmitting>(_ usage: inout B) throws {
    try Task.checkCancellation()
    try usage.consumeExactWork(1)
}
