import CADCore

package protocol CurvePositionEnclosing: Sendable {
  func enclosure(of curve: Curve3D, over parameters: ScalarInterval, tolerance: ModelingTolerance)
    throws -> CoordinateEnclosure3D
  func enclosure(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CoordinateEnclosure3D
}
