import CADCore

protocol CurveSpatialDerivativeRangeResolving: Sendable {
  func derivativeRange(curve: Curve3D, interval: ScalarInterval, tolerance: ModelingTolerance)
    throws -> CurveSpatialDerivativeRange?
  func derivativeRange(
    curve: Curve3D,
    interval: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveSpatialDerivativeRange?
}
