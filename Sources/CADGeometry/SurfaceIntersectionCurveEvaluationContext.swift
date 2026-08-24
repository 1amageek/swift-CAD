import CADCore

package final class SurfaceIntersectionCurveEvaluationContext {
    private let curve: any NormalizedSurfaceIntersectionCurveEvaluating
    private let firstSurface: Surface3D
    private let secondSurface: Surface3D
    private let tolerance: ModelingTolerance

    package init(
        curve: some NormalizedSurfaceIntersectionCurveEvaluating,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) {
        self.curve = curve
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        self.tolerance = tolerance
    }

    package func firstParameter(at fraction: Double) throws -> SurfaceParameter {
        try curve.parameter(
            on: firstSurface,
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    package func secondParameter(at fraction: Double) throws -> SurfaceParameter {
        try curve.parameter(
            on: secondSurface,
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    package func point(at fraction: Double) throws -> Point3D {
        try curve.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }
}
