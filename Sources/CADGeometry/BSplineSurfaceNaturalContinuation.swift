import CADCore

/// A B-spline surface read anywhere: inside its domain it is itself, and past it its end spans'
/// polynomials carry on (the natural extension, as Extend Sheet's natural shape continues a sheet).
/// Each row is evaluated along U, then the column of those points along V, by de Boor's algorithm
/// on the span nearest the parameter, in homogeneous coordinates so rational surfaces continue too.
package struct BSplineSurfaceNaturalContinuation: Sendable {
    private let surface: BSplineSurface3D

    package init(_ surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
        try surface.validate(tolerance: tolerance)
        self.surface = surface
    }

    package func point(u: Double, v: Double) -> Point3D {
        let rows = surface.controlPoints.indices.map { row in
            Self.deBoor(
                surface.controlPoints[row].indices.map { column in
                    let point = surface.controlPoints[row][column]
                    let weight = surface.weights[row][column]
                    return SIMD4(point.x * weight, point.y * weight, point.z * weight, weight)
                },
                knots: surface.uKnots, degree: surface.uDegree, at: u
            )
        }
        let homogeneous = Self.deBoor(rows, knots: surface.vKnots, degree: surface.vDegree, at: v)
        return Point3D(x: homogeneous.x / homogeneous.w, y: homogeneous.y / homogeneous.w, z: homogeneous.z / homogeneous.w)
    }

    /// The curve of `points` on `knots` at `t`, extrapolating the first or last span beyond them.
    private static func deBoor(_ points: [SIMD4<Double>], knots: [Double], degree p: Int, at t: Double) -> SIMD4<Double> {
        let n = points.count - 1
        var span = p
        while span < n, knots[span + 1] <= t { span += 1 }
        var d = (0...p).map { points[$0 + span - p] }
        for r in stride(from: 1, through: p, by: 1) {
            for j in stride(from: p, through: r, by: -1) {
                let i = j + span - p
                let alpha = (t - knots[i]) / (knots[i + p + 1 - r] - knots[i])
                d[j] = d[j - 1] * (1 - alpha) + d[j] * alpha
            }
        }
        return d[p]
    }
}
