import CADCore

public protocol CurveDifferentialEnclosing: Sendable {
  func enclosure(of curve: Curve3D, over parameters: ScalarInterval, tolerance: ModelingTolerance)
    throws -> CurveDifferentialEnclosure
  func enclosure(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveDifferentialEnclosure
}
