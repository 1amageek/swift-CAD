import CADCore

extension ExactRationalCoefficient {
    /// Brackets the exact rational by comparing candidate Double bits exactly.
    package func outwardInterval<B: RationalAlgebraAdmitting>(usage: inout B) throws -> OutwardScalarInterval {
        if isZero { return .exact(0) }
        func approximation(_ magnitude: ExactNaturalMagnitude) throws -> (Double, Int) {
            let words = magnitude.words
            guard let last = words.last else { return (0, 0) }
            try usage.consumeExactWork(2)
            let next = words.count > 1 ? words[words.count - 2] : 0
            let significand = Double(last) * 4_294_967_296 + Double(next)
            let shift = (words.count - 2).multipliedReportingOverflow(by: 32)
            guard !shift.overflow else { throw rationalAlgebraFailure("Exact rational interval exponent overflows.") }
            return (significand, shift.partialValue)
        }
        let n = try approximation(numerator), d = try approximation(denominator)
        let difference = n.1.subtractingReportingOverflow(d.1)
        guard !difference.overflow else { throw rationalAlgebraFailure("Exact rational interval exponent difference overflows.") }
        var candidate = Double(sign: sign < 0 ? .minus : .plus,
            exponent: difference.partialValue, significand: n.0 / d.0)
        guard candidate.isFinite else { throw rationalAlgebraFailure("Exact rational coefficient has no finite Double enclosure.") }
        var comparison = try subtracting(.originalDouble(candidate, usage: &usage), usage: &usage)
        if comparison.isZero { return .exact(candidate) }
        let below = comparison.isPositive
        while true {
            try usage.consumeExactWork(1)
            let adjacent = below ? candidate.nextUp : candidate.nextDown
            guard adjacent.isFinite else { throw rationalAlgebraFailure("Exact rational coefficient exceeds finite interval support.") }
            comparison = try subtracting(.originalDouble(adjacent, usage: &usage), usage: &usage)
            if comparison.isZero {
                return OutwardScalarInterval(lower: min(candidate, adjacent), upper: max(candidate, adjacent))
            }
            if comparison.isPositive != below {
                return OutwardScalarInterval(lower: min(candidate, adjacent), upper: max(candidate, adjacent))
            }
            candidate = adjacent
        }
    }
}

extension ExactBivariatePolynomial {
    /// Original polynomial enclosure; no interval coefficient is promoted to exact.
    package func enclosure<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        usage: inout B) throws -> OutwardScalarInterval {
        let u = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
        let v = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
        func power(_ value: OutwardScalarInterval, _ exponent: Int) throws -> OutwardScalarInterval {
            var result = OutwardScalarInterval.exact(1), factor = value, remaining = exponent
            while remaining > 0 {
                try usage.consumeExactWork(1)
                if remaining & 1 == 1 { result = result * factor }
                remaining >>= 1
                if remaining > 0 { factor = factor * factor }
            }
            return result
        }
        var result = OutwardScalarInterval.exact(0)
        for term in try orderedTerms(usage: &usage) {
            try usage.consumeExactWork(2)
            result = try result + term.value.outwardInterval(usage: &usage)
                * power(u, term.key.u) * power(v, term.key.v)
        }
        guard result.isFinite else { throw rationalAlgebraFailure("Original rational polynomial interval is nonfinite.") }
        return result
    }
}
