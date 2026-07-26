import CADCore

protocol BSplineSurfaceDerivativeRangeResolving: Sendable {
    func derivativeRanges(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    )
}
