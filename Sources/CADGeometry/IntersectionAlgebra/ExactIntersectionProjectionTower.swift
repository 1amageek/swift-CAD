import CADCore

/// Retains all full projection levels without issuing a real-cell certificate.
package struct ExactIntersectionProjectionTower: Sendable {
    package let variableCount: Int
    package let hasThomEncoding: Bool
    /// Descending axes: the original equations are retained by the first level.
    package let levels: [ExactIntersectionProjection]

    private init(variableCount: Int, levels: [ExactIntersectionProjection], hasThomEncoding: Bool) {
        self.variableCount = variableCount; self.levels = levels; self.hasThomEncoding = hasThomEncoding
    }

    package static func prepare<B: RationalAlgebraAdmitting>(
        sources: [ExactIntersectionPolynomial], variableCount: Int, thomEncoding: Bool = false,
        usage: inout B) throws -> Self {
        guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount) else {
            throw rationalAlgebraFailure("Projection tower requires a positive original predicate coordinate count.")
        }
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(variableCount, of: ExactIntersectionProjection.self, usage: &usage)
        var levels: [ExactIntersectionProjection] = []; levels.reserveCapacity(variableCount)
        var pending = sources
        for axis in stride(from: variableCount - 1, through: 0, by: -1) {
            try intersectionAlgebraStep(&usage)
            if thomEncoding { pending = try derivativeClosure(pending, at: axis, usage: &usage) }
            let level = try ExactIntersectionProjection.prepare(sources: pending,
                variableCount: variableCount, axis: axis, usage: &usage)
            levels.append(level)
            pending = level.polynomials
        }
        return Self(variableCount: variableCount, levels: levels, hasThomEncoding: thomEncoding)
    }
    package func retainedPrefix<B: RationalAlgebraAdmitting>(variableCount count: Int,
        sources: [ExactIntersectionPolynomial], usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        guard count > 0, count <= variableCount else {
            throw rationalAlgebraFailure("A retained projection prefix requires its original coordinate domain.")
        }
        let start = variableCount - count
        try RationalAlgebraStorage.retain(levels[start].sources.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        let known = try levels[start].sources.map { try $0.lowered(to: count, usage: &usage) }
        for source in sources {
            let normalized = try ExactIntersectionPolynomialGCD.squareFree(source, usage: &usage)
            if normalized.isConstant { continue }
            var found = false
            for polynomial in known {
                if try normalized.matches(polynomial.monic(usage: &usage), usage: &usage) { found = true; break }
            }
            if !found { return nil }
        }
        try RationalAlgebraStorage.retain(count, of: ExactIntersectionProjection.self, usage: &usage)
        var prefix: [ExactIntersectionProjection] = []; prefix.reserveCapacity(count)
        for index in start..<levels.count {
            prefix.append(try levels[index].lowered(to: count, sources: index == start ? sources : nil, usage: &usage))
        }
        return Self(variableCount: count, levels: prefix, hasThomEncoding: hasThomEncoding)
    }

    private static func derivativeClosure<B: RationalAlgebraAdmitting>(_ sources: [ExactIntersectionPolynomial],
        at axis: Int, usage: inout B) throws -> [ExactIntersectionPolynomial] {
        try RationalAlgebraStorage.retain(sources.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var result = sources
        for source in sources {
            var derivative = try source.differentiated(at: axis, usage: &usage)
            while !derivative.isZero {
                try intersectionAlgebraStep(&usage)
                var duplicate = false
                for existing in result {
                    if try existing.matches(derivative, usage: &usage) { duplicate = true; break }
                }
                if !duplicate {
                    try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                    result.append(derivative)
                }
                derivative = try derivative.differentiated(at: axis, usage: &usage)
            }
        }
        return result
    }

}
