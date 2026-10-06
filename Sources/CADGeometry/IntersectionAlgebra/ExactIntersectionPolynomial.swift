import CADCore

/// Original rational source polynomial; five coordinates include denominator saturation.
package struct ExactIntersectionPolynomial: Equatable, Sendable {
    package struct Power: Hashable, Sendable {
        let a: Int
        let b: Int
        let c: Int
        let d: Int
        let e: Int

        init(_ values: (Int, Int, Int, Int, Int), variableCount: Int) throws {
            guard (1...5).contains(variableCount),
                  values.0 >= 0, values.1 >= 0, values.2 >= 0,
                  values.3 >= 0, values.4 >= 0,
                  variableCount >= 2 || values.1 == 0,
                  variableCount >= 3 || values.2 == 0,
                  variableCount >= 4 || values.3 == 0,
                  variableCount >= 5 || values.4 == 0 else {
                throw rationalAlgebraFailure("Intersection powers do not belong to the original polynomial ring.")
            }
            a = values.0; b = values.1; c = values.2; d = values.3; e = values.4
        }

        func exponent(at coordinate: Int) throws -> Int {
            switch coordinate {
            case 0: return a
            case 1: return b
            case 2: return c
            case 3: return d
            case 4: return e
            default: throw rationalAlgebraFailure("Intersection polynomial coordinate is outside its ring.")
            }
        }

        func precedes(_ other: Self) -> Bool {
            if e != other.e { return e < other.e }
            if d != other.d { return d < other.d }
            if c != other.c { return c < other.c }
            if b != other.b { return b < other.b }
            return a < other.a
        }

        func divides(_ other: Self) -> Bool {
            a <= other.a && b <= other.b && c <= other.c && d <= other.d && e <= other.e
        }

        func sum(_ other: Self, variableCount: Int) throws -> Self {
            try Self((rationalAlgebraCount(a, other.a), rationalAlgebraCount(b, other.b),
                      rationalAlgebraCount(c, other.c), rationalAlgebraCount(d, other.d),
                      rationalAlgebraCount(e, other.e)), variableCount: variableCount)
        }

        func quotient(by other: Self, variableCount: Int) throws -> Self {
            guard other.divides(self) else {
                throw rationalAlgebraFailure("Intersection monomial division has a negative exponent.")
            }
            return try Self((a - other.a, b - other.b, c - other.c, d - other.d, e - other.e),
                            variableCount: variableCount)
        }

        func leastCommonMultiple(_ other: Self, variableCount: Int) throws -> Self {
            try Self((max(a, other.a), max(b, other.b), max(c, other.c),
                      max(d, other.d), max(e, other.e)), variableCount: variableCount)
        }
    }

    package let variableCount: Int
    private let coefficients: [Power: ExactRationalCoefficient]

    private init(variableCount: Int, coefficients: [Power: ExactRationalCoefficient]) {
        self.variableCount = variableCount
        self.coefficients = coefficients
    }

    package var isZero: Bool { coefficients.isEmpty }
    package var isConstant: Bool {
        if coefficients.isEmpty { return true }
        guard coefficients.count == 1, let power = coefficients.first?.key else { return false }
        return power.a == 0 && power.b == 0 && power.c == 0 && power.d == 0 && power.e == 0
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
        guard (1...5).contains(variableCount) else {
            throw rationalAlgebraFailure("Intersection polynomial ring requires one through five coordinates.")
        }
        return Self(variableCount: variableCount, coefficients: [:])
    }

    package static func monomial<B: RationalAlgebraAdmitting>(variableCount: Int,
        powers: (Int, Int, Int, Int, Int), coefficient: ExactRationalCoefficient,
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
                     coordinate == 4 ? 1 : 0), coefficient: .one, usage: &usage)
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
                         uCoordinate == 4 ? power.u : vCoordinate == 4 ? power.v : 0),
                coefficient: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }

    package func lifted<B: RationalAlgebraAdmitting>(to count: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard count >= variableCount, count <= 5 else {
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
                powers: (reduced.a, reduced.b, reduced.c, reduced.d, reduced.e),
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
        return try scaled(by: .one.divided(by: lead.coefficient, usage: &usage), usage: &usage)
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
