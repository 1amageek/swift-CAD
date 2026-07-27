import CADCore

protocol BSplineSurfaceDerivativeRangeResolving: Sendable {
    func derivativeRanges(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    )

    func derivativeRanges(
        patches: [RationalBezierSurfacePatch3D],
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    )
}
