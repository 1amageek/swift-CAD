import CADCore

/// Complete distinct real tuples of a verified finite original rational ideal.
package struct OriginalFiniteIntersectionFiber: Sendable {
    package struct Point: Sendable {
        package let context: OriginalSingularFieldContext
        package let coordinates: [OriginalSingularFieldElement]
        package let coordinateRoots: [OriginalSingularFieldRoot]
    }

    package let ideal: ExactIntersectionIdeal
    package let domains: [ScalarInterval?]
    package let points: [Point]

    private init(ideal: ExactIntersectionIdeal, domains: [ScalarInterval?], points: [Point]) {
        self.ideal = ideal; self.domains = domains; self.points = points
    }

    /// Holds the exclusively borrowed ledger value, never a fresh allowance.


    package static func prepare<B: ExactScalarAdmission & ~Copyable>(ideal: ExactIntersectionIdeal,
        domains: [ScalarInterval?], maximumDepth: Int, usage: inout B) throws -> Self {
        return try prepareAdmitted(ideal: ideal, domains: domains,
            maximumDepth: maximumDepth, usage: &usage)
    }

    private static func prepareAdmitted<B: ExactScalarAdmission & ~Copyable>(ideal: ExactIntersectionIdeal,
        domains: [ScalarInterval?], maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard domains.count == ideal.variableCount, maximumDepth >= 0,
              domains.allSatisfy({ $0.map { $0.lower.isFinite && $0.upper.isFinite } ?? true }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Finite intersection lifting requires one closed or unrestricted domain per original coordinate.")
        }
        switch ideal.classification {
        case .inconsistent:
            return Self(ideal: ideal, domains: domains, points: [])
        case .positiveDimensional:
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Finite real lifting requires a zero-dimensional ideal; complex dimension cannot classify its real strata.")
        case .zeroDimensional: break
        }
        let rational = try OriginalSingularFieldContext(usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
        var prefixes = [Point(context: rational, coordinates: [], coordinateRoots: [])]
        for coordinate in 0..<ideal.variableCount {
            try intersectionAlgebraStep(&usage)
            var next: [Point] = []
            for prefix in prefixes {
                try intersectionAlgebraStep(&usage)
                var common: OriginalSingularFieldPolynomial?
                for polynomial in ideal.reducedBasis {
                    guard let specialized = try OriginalIntersectionFieldEvaluation.specialized(polynomial, at: coordinate,
                        context: prefix.context, coordinates: prefix.coordinates, maximumDepth: maximumDepth, usage: &usage),
                        !specialized.isZero else { continue }
                    if let retained = common {
                        common = try .gcd(retained, specialized, maximumDepth: maximumDepth, usage: &usage)
                    } else { common = specialized }
                    if common?.degree == 0 { break }
                }
                guard let common else {
                    throw rationalAlgebraFailure("A finite original leading ideal lost its monic coordinate equation.")
                }
                if common.degree == 0 { continue }
                let roots = try OriginalSingularFieldRoot.allRealRoots(common,
                    inheritedDepth: prefix.context.depth, maximumDepth: maximumDepth, usage: &usage)
                for root in roots {
                    try intersectionAlgebraStep(&usage)
                    let value: OriginalSingularFieldElement
                    if root.polynomial.degree == 1 {
                        value = try root.polynomial.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                            .divided(by: root.polynomial.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                    } else { value = try root.value(maximumDepth: maximumDepth, usage: &usage) }
                    guard try contains(value, in: domains[coordinate],
                        maximumDepth: maximumDepth, usage: &usage) else { continue }
                    let count = try rationalAlgebraCount(prefix.coordinates.count, 1)
                    try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
                    var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(count)
                    for original in prefix.coordinates {
                        values.append(try original.embedded(in: value.context,
                            maximumDepth: maximumDepth, usage: &usage))
                    }
                    values.append(value)
                    try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldRoot.self, usage: &usage)
                    var witnesses = prefix.coordinateRoots
                    witnesses.append(root)
                    try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
                    next.append(Point(context: value.context, coordinates: values, coordinateRoots: witnesses))
                }
            }
            prefixes = next
            if prefixes.isEmpty { break }
        }
        for point in prefixes {
            guard point.coordinates.count == ideal.variableCount,
                  point.coordinateRoots.count == ideal.variableCount else {
                throw rationalAlgebraFailure("Original finite lifting published an incomplete parameter tuple.")
            }
            for equation in ideal.originalEquations {
                let scalar = try OriginalIntersectionFieldEvaluation.evaluated(equation, context: point.context,
                    coordinates: point.coordinates, maximumDepth: maximumDepth, usage: &usage)
                guard case .zero = try scalar.sign(maximumDepth: maximumDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("A lifted tuple does not satisfy every original intersection equation.")
                }
            }
        }
        try RationalAlgebraStorage.retain(domains.count, of: ScalarInterval?.self, usage: &usage)
        return Self(ideal: ideal, domains: domains, points: prefixes)
    }

    private static func contains<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        in domain: ScalarInterval?, maximumDepth: Int, usage: inout B) throws -> Bool {
        guard let domain else { return true }
        let lower = try OriginalSingularFieldElement.constant(.originalDouble(domain.lower, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        let upper = try OriginalSingularFieldElement.constant(.originalDouble(domain.upper, usage: &usage),
            in: value.context, maximumDepth: maximumDepth, usage: &usage)
        if case .negative = try value.subtracting(lower, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        if case .negative = try upper.subtracting(value, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        return true
    }
}
