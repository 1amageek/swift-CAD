import CADCore

/// Full rational projection preparation; does not publish real cells or intersections.
package struct ExactIntersectionProjection: Sendable {
    private typealias Polynomial = ExactIntersectionPolynomial
    package let axis: Int
    package let sources: [ExactIntersectionPolynomial]
    package let polynomials: [ExactIntersectionPolynomial]

    private init(axis: Int, sources: [ExactIntersectionPolynomial], polynomials: [ExactIntersectionPolynomial]) {
        self.axis = axis; self.sources = sources; self.polynomials = polynomials
    }

    package func lowered<B: RationalAlgebraAdmitting>(to count: Int,
        sources replacement: [ExactIntersectionPolynomial]? = nil, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard axis < count else { throw rationalAlgebraFailure("A retained projection axis is outside its prefix.") }
        try RationalAlgebraStorage.retain(sources.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        let original = try sources.map { try $0.lowered(to: count, usage: &usage) }
        try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        let projected = try polynomials.map { try $0.lowered(to: count, usage: &usage) }
        return Self(axis: axis, sources: replacement ?? original, polynomials: projected)
    }

    package static func prepare<B: RationalAlgebraAdmitting>(
        sources: [ExactIntersectionPolynomial], variableCount: Int, axis: Int,
        usage: inout B) throws -> Self {
        guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount), axis >= 0, axis < variableCount else {
            throw rationalAlgebraFailure("Projection requires a bound axis and one original polynomial ring.")
        }
        for source in sources {
            try intersectionAlgebraStep(&usage)
            guard source.variableCount == variableCount else {
                throw rationalAlgebraFailure("Projection sources do not share one original polynomial ring.")
            }
        }
        // Projection is a set operation; retain original truth sources separately.
        var active: [Polynomial] = []
        for source in sources { try insert(source, into: &active, usage: &usage) }
        try splitCommonFactors(&active, usage: &usage)
        typealias Prepared = ExactIntersectionSubresultants.PreparedPolynomial
        try RationalAlgebraStorage.retain(active.count, of: [Prepared].self, usage: &usage)
        var families: [[Prepared]] = []
        var projected: [Polynomial] = []
        var projectedIndex = MembershipIndex()
        let coordinate = try Polynomial.coordinate(variableCount: variableCount, at: axis, usage: &usage)
        for source in active {
            try intersectionAlgebraStep(&usage)
            let original = try Prepared(source, axis: axis, usage: &usage)
            let coefficients = original.coefficients
            var reducta: [Prepared] = []
            var remainder = source
            var degree = coefficients.count - 1
            while degree >= 0 {
                try intersectionAlgebraStep(&usage)
                if coefficients[degree].isZero { degree -= 1; continue }
                if degree == 0 {
                    try insert(remainder, into: &projected, index: &projectedIndex, usage: &usage)
                    break
                }
                let prepared = degree == coefficients.count - 1 ? original :
                    try Prepared(remainder, axis: axis, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Prepared.self, usage: &usage)
                reducta.append(prepared)
                try insert(coefficients[degree], into: &projected, index: &projectedIndex, usage: &usage)
                let derivative = try remainder.differentiated(at: axis, usage: &usage)
                for coefficient in try ExactIntersectionSubresultants.principal(
                    prepared, Prepared(derivative, axis: axis, usage: &usage), usage: &usage) {
                    try insert(coefficient, into: &projected, index: &projectedIndex, usage: &usage)
                }
                var leadingTerm = coefficients[degree]
                for _ in 0..<degree {
                    leadingTerm = try leadingTerm.multiplied(by: coordinate, usage: &usage)
                }
                remainder = try remainder.subtracting(leadingTerm, usage: &usage)
                degree -= 1
            }
            families.append(reducta)
        }
        for first in families.indices {
            for second in (first + 1)..<families.count {
                try intersectionAlgebraStep(&usage)
                for a in families[first] {
                    for b in families[second] {
                        for coefficient in try ExactIntersectionSubresultants.principal(
                            a, b, usage: &usage) {
                            try insert(coefficient, into: &projected, index: &projectedIndex, usage: &usage)
                        }
                    }
                }
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return Self(axis: axis, sources: sources, polynomials: projected)
    }

    /// Query-local candidate offsets; hash equality never establishes polynomial equality.
    private struct MembershipIndex {
        private var heads: [Int: Int] = [:]
        private var previous: [Int] = []
        private var headCapacity = 0
        private var linkCapacity = 0

        func contains<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial, fingerprint: Int,
            in result: [Polynomial], usage: inout B) throws -> Bool {
            try intersectionAlgebraStep(&usage)
            var offset = heads[fingerprint] ?? -1
            while offset >= 0 {
                try intersectionAlgebraStep(&usage)
                if try result[offset].matches(polynomial, usage: &usage) { return true }
                offset = previous[offset]
            }
            return false
        }

        mutating func retain<B: RationalAlgebraAdmitting>(_ fingerprint: Int,
            offset: Int, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            guard offset == previous.count else {
                throw rationalAlgebraFailure("Projection membership offsets contradict their retained set.")
            }
            let required = try rationalAlgebraCount(previous.count, 1)
            if required > linkCapacity {
                let capacity = linkCapacity == 0 ? 16 : try rationalAlgebraCount(linkCapacity, linkCapacity)
                try RationalAlgebraStorage.retain(capacity, of: Int.self, usage: &usage)
                try usage.consumeExactWork(previous.count)
                try CurrentTaskCancellationChecker().checkCancellation()
                previous.reserveCapacity(capacity)
                linkCapacity = capacity
            }
            if heads[fingerprint] == nil && heads.count == headCapacity {
                let capacity = headCapacity == 0 ? 16 : try rationalAlgebraCount(headCapacity, headCapacity)
                // Admit the full new hash table, including occupancy/offset overhead,
                // before reserve can replace its previous uniquely owned buffer.
                try RationalAlgebraStorage.retain(try rationalAlgebraCount(capacity, capacity),
                    of: (Int, Int).self, usage: &usage)
                try usage.consumeExactWork(heads.count)
                try CurrentTaskCancellationChecker().checkCancellation()
                heads.reserveCapacity(capacity)
                headCapacity = capacity
            }
            previous.append(heads[fingerprint] ?? -1)
            heads[fingerprint] = offset
        }
    }

    private static func fingerprint<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial,
        usage: inout B) throws -> Int {
        try intersectionAlgebraStep(&usage)
        var hash = Hasher()
        hash.combine(polynomial.variableCount)
        let terms = try polynomial.orderedTerms(usage: &usage)
        hash.combine(terms.count)
        for (power, coefficient) in terms {
            try intersectionAlgebraStep(&usage)
            let numerator = coefficient.canonicalNumeratorWords
            let denominator = coefficient.canonicalDenominatorWords
            let coefficientCount = try rationalAlgebraCount(numerator.count, denominator.count)
            try usage.consumeExactWork(try rationalAlgebraCount(
                try rationalAlgebraCount(12, power.overflowCount), coefficientCount))
            try CurrentTaskCancellationChecker().checkCancellation()
            hash.combine(power)
            hash.combine(coefficient.canonicalSign)
            hash.combine(numerator.count)
            for word in numerator { hash.combine(word) }
            hash.combine(denominator.count)
            for word in denominator { hash.combine(word) }
        }
        return hash.finalize()
    }

    private static func insert<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial,
        into result: inout [Polynomial], index: inout MembershipIndex, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        if polynomial.isZero || polynomial.isConstant { return }
        let monic = try polynomial.monic(usage: &usage)
        if try index.contains(monic, fingerprint: fingerprint(monic, usage: &usage),
            in: result, usage: &usage) { return }
        let normalized = try ExactIntersectionPolynomialGCD.squareFree(polynomial, usage: &usage)
        let key = try fingerprint(normalized, usage: &usage)
        if try index.contains(normalized, fingerprint: key, in: result, usage: &usage) { return }
        try RationalAlgebraStorage.retain(1, of: Polynomial.self, usage: &usage)
        try index.retain(key, offset: result.count, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        result.append(normalized)
    }

    private static func insert<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial,
        into result: inout [Polynomial], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        if polynomial.isZero || polynomial.isConstant { return }
        let monic = try polynomial.monic(usage: &usage)
        // Existing entries already own a verified square-free law. Equality
        // proves this incoming original needs no second normalization.
        for existing in result {
            if try existing.matches(monic, usage: &usage) { return }
        }
        let normalized = try ExactIntersectionPolynomialGCD.squareFree(polynomial, usage: &usage)
        for existing in result {
            if try existing.matches(normalized, usage: &usage) { return }
        }
        try RationalAlgebraStorage.retain(1, of: Polynomial.self, usage: &usage)
        result.append(normalized)
    }

    private static func insertVerifiedSquareFree<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial,
        into result: inout [Polynomial], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        if polynomial.isZero || polynomial.isConstant { return }
        let normalized = try polynomial.monic(usage: &usage)
        for existing in result {
            if try existing.matches(normalized, usage: &usage) { return }
        }
        try RationalAlgebraStorage.retain(1, of: Polynomial.self, usage: &usage)
        result.append(normalized)
    }

    private static func splitCommonFactors<B: RationalAlgebraAdmitting>(_ basis: inout [Polynomial],
        usage: inout B) throws {
        var first = 0
        while first < basis.count {
            var second = first + 1
            while second < basis.count {
                try intersectionAlgebraStep(&usage)
                let common = try ExactIntersectionPolynomialGCD.gcd(basis[first], basis[second], usage: &usage)
                if common.isConstant { second += 1; continue }
                let a = try basis[first].dividedExactly(by: common, usage: &usage)
                let b = try basis[second].dividedExactly(by: common, usage: &usage)
                basis[first] = common
                try usage.consumeExactWork(basis.count - second)
                basis.remove(at: second)
                // Exact divisors inherit square-freeness and every earlier unit
                // GCD proof. Keep the next candidate at the removed position;
                // dynamic later rows also visit newly appended factors.
                try insertVerifiedSquareFree(a, into: &basis, usage: &usage)
                try insertVerifiedSquareFree(b, into: &basis, usage: &usage)
            }
            first += 1
        }
    }
}
