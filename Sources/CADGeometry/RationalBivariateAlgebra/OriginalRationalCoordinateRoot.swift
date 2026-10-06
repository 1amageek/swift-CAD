/// Original algebraic coordinate transport with retained parameter existence and causal depth.
package struct OriginalRationalCoordinateRoot {
    private struct Interval {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient

        func adding<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
            usage: inout B) throws -> Self {
            try .init(lower: lower.adding(value, usage: &usage), upper: upper.adding(value, usage: &usage))
        }
        func divided<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self? {
            guard other.lower.isPositive || other.upper.isNegative else { return nil }
            let reciprocal = try Interval(lower: .one.divided(by: other.upper, usage: &usage),
                upper: .one.divided(by: other.lower, usage: &usage))
            return try multiplied(by: reciprocal, usage: &usage)
        }
        func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
            try usage.retainExactStorage(4)
            let values = try [lower.multiplied(by: other.lower, usage: &usage),
                lower.multiplied(by: other.upper, usage: &usage),
                upper.multiplied(by: other.lower, usage: &usage), upper.multiplied(by: other.upper, usage: &usage)]
            var low = values[0], high = values[0]
            for value in values {
                if try value.subtracting(low, usage: &usage).isNegative { low = value }
                if try value.subtracting(high, usage: &usage).isPositive { high = value }
            }
            return .init(lower: low, upper: high)
        }
    }
    private struct DepthOffset<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var base: B
        let offset: Int
        mutating func visitExactCell(depth: Int) throws {
            try base.visitExactCell(depth: rationalAlgebraCount(offset, depth))
        }
        mutating func visitCoefficientCell(depth: Int) throws { try base.visitCoefficientCell(depth: depth) }
        mutating func consumeExactWork(_ count: Int) throws { try base.consumeExactWork(count) }
        mutating func retainExactStorage(_ count: Int) throws { try base.retainExactStorage(count) }
    }

    package static func coordinate<B: RationalAlgebraAdmitting>(numerator: ExactBivariatePolynomial,
        denominator: ExactBivariatePolynomial, at endpoint: ExactMonotoneGraphEndpoint,
        maximumDepth: Int, usage: inout B) throws -> ExactMonotoneGraphEndpoint {
        guard numerator.vDegree <= 0, denominator.vDegree <= 0, !denominator.isZero,
            maximumDepth >= endpoint.depth else {
            throw rationalAlgebraFailure("Original rational coordinate transport needs retained univariate laws and causal depth.")
        }
        if case .zero = try endpoint.sign(of: denominator, maximumDepth: maximumDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original rational coordinate denominator vanishes at the retained parameter.")
        }
        switch endpoint {
        case .authored(let station):
            return try .authored(numerator.evaluated(atU: station, v: .zero, usage: &usage)
                .divided(by: denominator.evaluated(atU: station, v: .zero, usage: &usage), usage: &usage))
        case .algebraic(let parameter):
            let gcd = ExactBivariateGCD()
            let poles = try gcd.univariateGCD(parameter.polynomial, denominator, usage: &usage)
            let originalParameter = try parameter.polynomial.dividedExactly(by: poles, usage: &usage)
            guard originalParameter.uDegree > 0 else {
                throw rationalAlgebraFailure("Original rational coordinate lost its nonpole parameter root.")
            }
            let n = try gcd.univariateDivision(numerator, originalParameter, usage: &usage).remainder
            let d = try gcd.univariateDivision(denominator, originalParameter, usage: &usage).remainder
            guard let leading = d.leading?.value else {
                throw rationalAlgebraFailure("Original rational coordinate remainder denominator contradicts its nonpole source root.")
            }
            let value = try (n.leading?.value ?? .zero).divided(by: leading, usage: &usage)
            if try n.subtracting(d.scaled(by: value, usage: &usage), usage: &usage).isZero { return .authored(value) }
            let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            let equation = try x.multiplied(by: denominator.exchangedAxes(usage: &usage), usage: &usage)
                .subtracting(numerator.exchangedAxes(usage: &usage), usage: &usage)
            let projected = try ExactBivariateResultant().eliminatingV(
                originalParameter.exchangedAxes(usage: &usage), equation, usage: &usage)
            guard projected.uDegree > 0 else {
                throw rationalAlgebraFailure("Original rational coordinate transport lost its algebraic image equation.")
            }
            var current = endpoint
            let two = try ExactRationalCoefficient.natural(2, usage: &usage)
            while true {
                let n = try image(numerator, lower: current.lower, upper: current.upper, usage: &usage)
                let d = try image(denominator, lower: current.lower, upper: current.upper, usage: &usage)
                if let range = try n.divided(by: d, usage: &usage) {
                    if range.lower == range.upper { return .authored(range.lower) }
                    guard maximumDepth >= current.depth else {
                        throw rationalAlgebraFailure("Original coordinate transport exceeded its retained source depth.")
                    }
                    let roots: [ExactUnivariateRootIsolator.Root]
                    do {
                        var offset = DepthOffset(base: usage, offset: current.depth)
                        defer { usage = offset.base }
                        roots = try ExactUnivariateRootIsolator().isolate(projected, lower: range.lower,
                            upper: range.upper, maximumDepth: maximumDepth - current.depth, usage: &offset)
                    }
                    guard !roots.isEmpty else {
                        throw rationalAlgebraFailure("Original coordinate resultant contradicts retained parameter existence.")
                    }
                    if roots.count == 1 {
                        let source = roots[0]
                        let retained = try ExactUnivariateRootIsolator.Root(lower: source.lower, upper: source.upper,
                            isRationalStation: source.isRationalStation,
                            isolationDepth: rationalAlgebraCount(current.depth, source.isolationDepth),
                            excludesLowerEndpoint: source.excludesLowerEndpoint, excludesUpperEndpoint: source.excludesUpperEndpoint)
                        try usage.visitExactCell(depth: retained.isolationDepth)
                        return try .algebraic(ExactAlgebraicRealRoot(polynomial: projected, isolation: retained, usage: &usage))
                    }
                }
                let width = try current.upper.subtracting(current.lower, usage: &usage)
                guard width.isPositive else {
                    throw rationalAlgebraFailure("Original rational coordinate has a conflicting singleton source image.")
                }
                current = try current.refined(maximumWidth: width.divided(by: two, usage: &usage),
                    maximumDepth: maximumDepth, usage: &usage)
            }
        }
    }

    private static func image<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        usage: inout B) throws -> Interval {
        let terms = try polynomial.orderedTerms(usage: &usage)
        var value = Interval(lower: .zero, upper: .zero)
        let variable = Interval(lower: lower, upper: upper)
        var degree = max(0, polynomial.uDegree)
        while true {
            try usage.consumeExactWork(max(1, terms.count))
            let coefficient = terms.first(where: { $0.0.u == degree && $0.0.v == 0 })?.1 ?? .zero
            value = try value.adding(coefficient, usage: &usage)
            if degree == 0 { return value }
            value = try value.multiplied(by: variable, usage: &usage)
            degree -= 1
        }
    }
}
