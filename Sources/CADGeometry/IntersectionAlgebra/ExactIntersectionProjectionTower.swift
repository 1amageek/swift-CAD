import CADCore

/// Retains all full projection levels without issuing a real-cell certificate.
package struct ExactIntersectionProjectionTower: Sendable {
    package let variableCount: Int
    /// Descending axes: the original equations are retained by the first level.
    package let levels: [ExactIntersectionProjection]

    private init(variableCount: Int, levels: [ExactIntersectionProjection]) {
        self.variableCount = variableCount; self.levels = levels
    }

    package static func prepare<B: RationalAlgebraAdmitting>(
        sources: [ExactIntersectionPolynomial], variableCount: Int,
        usage: inout B) throws -> Self {
        guard (1...5).contains(variableCount) else {
            throw rationalAlgebraFailure("Projection tower requires one through five original coordinates.")
        }
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(variableCount, of: ExactIntersectionProjection.self, usage: &usage)
        var levels: [ExactIntersectionProjection] = []; levels.reserveCapacity(variableCount)
        var pending = sources
        for axis in stride(from: variableCount - 1, through: 0, by: -1) {
            try intersectionAlgebraStep(&usage)
            let level = try ExactIntersectionProjection.prepare(sources: pending,
                variableCount: variableCount, axis: axis, usage: &usage)
            levels.append(level)
            pending = level.polynomials
        }
        return Self(variableCount: variableCount, levels: levels)
    }
}
