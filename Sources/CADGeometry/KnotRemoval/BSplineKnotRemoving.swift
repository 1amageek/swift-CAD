import CADCore

public protocol BSplineKnotRemoving: Sendable {
    func reducingMultiplicity(of source: BSplineCurve3D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions,
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineCurve3D>
    func reducingMultiplicity(of source: BSplineCurve2D, at knot: Double, to target: Int,
        maximumDeviation: Double, options: BSplineKnotRemovalOptions,
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineCurve2D>
    func reducingMultiplicity(of source: BSplineSurface3D, direction: SurfaceParameterDirection,
        at knot: Double, to target: Int, maximumDeviation: Double,
        options: BSplineKnotRemovalOptions,
        tolerance: ModelingTolerance) throws -> BSplineKnotRemovalResult<BSplineSurface3D>
}
