import CADCore

/// Complete finite original ideal fibers over a selected singular-resolution field.
package struct OriginalSingularFieldSystemSolver {
    package enum Result: Sendable {
        case finite([OriginalSingularFieldSystemRoot])
        case positiveDimension(equations: [OriginalSingularFieldPlanePolynomial], basis: [OriginalSingularFieldPlanePolynomial])
    }
    package static func roots<B: ExactScalarAdmission & ~Copyable>(of equations: [OriginalSingularFieldPlanePolynomial],
        over domain: SurfaceParameterBox, inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws -> Result {
        guard let first = equations.first, domain.u.width > 0, domain.v.width > 0, maximumDepth >= inheritedDepth else {
            throw rationalAlgebraFailure("Original ordered-field system needs source equations, rectangle and admitted depth.")
        }
        for equation in equations {
            guard equation.context === first.context else { throw rationalAlgebraFailure("Original ordered-field system has unrelated source contexts.") }
        }
        let basis = try OriginalSingularFieldGroebnerBasis.reducedBasis(equations, maximumDepth: maximumDepth, usage: &usage)
        var projection: OriginalSingularFieldPlanePolynomial?, pureV = false
        for value in basis {
            guard let leading = try value.leading(usage: &usage) else { continue }
            if leading.key.u == 0, leading.key.v == 0 { return .finite([]) }
            if leading.key.v == 0, leading.key.u > 0 { projection = value }
            if leading.key.u == 0, leading.key.v > 0 { pureV = true }
        }
        guard let projection, pureV else { return .positiveDimension(equations: equations, basis: basis) }
        let univariate = try Self.projected(projection, maximumDepth: maximumDepth, usage: &usage)
        let stations = try OriginalSingularFieldRoot.allRealRoots(univariate,
            inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage)
        var result: [OriginalSingularFieldSystemRoot] = []
        for station in stations {
            let u = try station.value(maximumDepth: maximumDepth, usage: &usage)
            guard try inside(u, interval: domain.u, maximumDepth: maximumDepth, usage: &usage) else { continue }
            var common = try OriginalSingularFieldPolynomial(context: u.context, coefficients: [], maximumDepth: maximumDepth, usage: &usage)
            for equation in equations {
                let value = try fiber(equation, at: u, maximumDepth: maximumDepth, usage: &usage)
                common = try OriginalSingularFieldPolynomial.gcd(common, value, maximumDepth: maximumDepth, usage: &usage)
            }
            if common.isZero { return .positiveDimension(equations: equations, basis: basis) }
            let fibers = try OriginalSingularFieldRoot.allRealRoots(common,
                inheritedDepth: station.isolation.depth, maximumDepth: maximumDepth, usage: &usage)
            for fiberRoot in fibers {
                let v = try fiberRoot.value(maximumDepth: maximumDepth, usage: &usage)
                guard try inside(v, interval: domain.v, maximumDepth: maximumDepth, usage: &usage) else { continue }
                let point = OriginalSingularFieldSystemRoot(equations: equations, projectionRoot: station,
                    fiberRoot: fiberRoot, u: u, v: v, sourceDomain: domain)
                for equation in equations {
                    guard case .zero = try point.sign(of: equation, maximumDepth: maximumDepth, usage: &usage) else {
                        throw rationalAlgebraFailure("Original ordered-field fiber is not a zero of every source equation.")
                    }
                }
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
                result.append(point)
            }
        }
        return .finite(result)
    }

    static func projected<B: ExactScalarAdmission & ~Copyable>(_ source: OriginalSingularFieldPlanePolynomial,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        guard source.vDegree <= 0 else { throw rationalAlgebraFailure("Original ordered-field projection is not univariate.") }
        let zero = try OriginalSingularFieldElement.constant(.zero, in: source.context, maximumDepth: maximumDepth, usage: &usage)
        let count = try rationalAlgebraCount(source.uDegree, 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for (power, coefficient) in try source.orderedTerms(usage: &usage) { values[power.u] = coefficient }
        return try .init(context: source.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    static func fiber<B: ExactScalarAdmission & ~Copyable>(_ source: OriginalSingularFieldPlanePolynomial,
        at u: OriginalSingularFieldElement, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        if source.isZero { return try .init(context: u.context, coefficients: [], maximumDepth: maximumDepth, usage: &usage) }
        let zero = try OriginalSingularFieldElement.constant(.zero, in: u.context, maximumDepth: maximumDepth, usage: &usage)
        let count = try rationalAlgebraCount(source.vDegree, 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values = Array(repeating: zero, count: count)
        for (power, coefficient) in try source.orderedTerms(usage: &usage) {
            var term = try coefficient.embedded(in: u.context, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<power.u { term = try term.multiplied(by: u, maximumDepth: maximumDepth, usage: &usage) }
            values[power.v] = try values[power.v].adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return try .init(context: u.context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        interval: ScalarInterval, maximumDepth: Int, usage: inout B) throws -> Bool {
        let low = try OriginalSingularFieldElement.constant(.originalDouble(interval.lower, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        let high = try OriginalSingularFieldElement.constant(.originalDouble(interval.upper, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        if case .negative = try value.subtracting(low, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        if case .positive = try value.subtracting(high, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        return true
    }
}
