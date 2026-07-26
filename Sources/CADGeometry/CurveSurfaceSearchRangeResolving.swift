import CADCore

protocol CurveSurfaceSearchRangeResolving: Sendable {
    func curveRange(
        curve: Curve3D,
        surface: Surface3D,
        requestedRange: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval
}
