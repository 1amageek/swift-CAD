import CADCore

/// A B-spline surface read anywhere: inside its domain it is itself, and past it its end spans'
/// polynomials carry on (the natural extension, as Extend Sheet's natural shape continues a sheet).
/// Each row is evaluated along U, then the column of those points along V, by de Boor's algorithm
/// on the span nearest the parameter, in homogeneous coordinates so rational surfaces continue too.
package struct BSplineSurfaceNaturalContinuation: Sendable {
    private let surface: BSplineSurface3D
    private let receipt: OriginalGeometryPreparationReceipt

    package init(_ surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface, tolerance: tolerance, using: &execution)
    }

    package init(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        let preparation = try execution.withPreparationScope { execution in
            try surface.validate(tolerance: tolerance, using: &execution)
        }
        self.surface = surface
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: preparation.depth, using: &execution)
    }

    package func point(u: Double, v: Double) throws -> Point3D {
        var execution = try receipt.makeExecution()
        return try point(u: u, v: v, using: &execution)
    }

    package func point(u: Double, v: Double,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        // Refuse mapped caller depths before paid retained-contribution attachment.
        try execution.admitDepth(value: receipt.depth.scalar.value, coefficient: receipt.depth.scalar.coefficient)
        try execution.admitSourceDepth(receipt.depth.sourceDepth)
        try execution.admitGeometricDepth(receipt.depth.geometricDepth)
        try execution.admitTransportDepth(receipt.depth.transportDepth)
        return try receipt.withContributionScopes(using: &execution) { execution in
            try receipt.admit(tolerance: receipt.tolerance, using: &execution)
            let rows = try OriginalCoefficientAllocation.map(elements: surface.controlPoints.indices,
                using: &execution) { row, execution in
                try Self.deBoor(
                    OriginalCoefficientAllocation.map(elements: surface.controlPoints[row].indices,
                        using: &execution) { column, _ in
                        let point = surface.controlPoints[row][column]
                        let weight = surface.weights[row][column]
                        return SIMD4(point.x * weight, point.y * weight, point.z * weight, weight)
                    },
                    knots: surface.uKnots, degree: surface.uDegree, at: u, using: &execution
                )
            }
            let homogeneous = try Self.deBoor(rows, knots: surface.vKnots, degree: surface.vDegree,
                at: v, using: &execution)
            try execution.consumeWork(1)
            let point = Point3D(x: homogeneous.x / homogeneous.w,
                y: homogeneous.y / homogeneous.w, z: homogeneous.z / homogeneous.w)
            try point.validate()
            return point
        }
    }

    /// The curve of `points` on `knots` at `t`, extrapolating the first or last span beyond them.
    private static func deBoor(_ points: [SIMD4<Double>], knots: [Double], degree p: Int, at t: Double,
        using execution: inout OriginalQueryExecution) throws -> SIMD4<Double> {
        try execution.consumeWork(1)
        let n = points.count - 1
        var span = p
        while span < n, knots[span + 1] <= t {
            try execution.consumeWork(1)
            span += 1
        }
        var d = try OriginalCoefficientAllocation.map(elements: 0...p, using: &execution) { index, _ in
            points[index + span - p]
        }
        for r in stride(from: 1, through: p, by: 1) {
            for j in stride(from: p, through: r, by: -1) {
                try execution.consumeWork(1)
                let i = j + span - p
                let alpha = (t - knots[i]) / (knots[i + p + 1 - r] - knots[i])
                d[j] = d[j - 1] * (1 - alpha) + d[j] * alpha
            }
        }
        return d[p]
    }
}
