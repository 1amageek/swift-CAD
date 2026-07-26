import CADCore

protocol CurveSpatialDerivativeRangeResolving: Sendable {
    func derivativeRange(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveSpatialDerivativeRange?
}
