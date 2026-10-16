import CADCore

package struct DefaultCurvePositionEncloser: CurvePositionEnclosing, Sendable {
  package init() {}

  package func enclosure(
    of curve: Curve3D, over parameters: ScalarInterval, tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try enclosure(of: curve, over: parameters, tolerance: tolerance, using: &execution)
  }

  package func enclosure(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CoordinateEnclosure3D {
    let result = try enclosureBody(
      of: curve, over: parameters, tolerance: tolerance, using: &execution)
    try execution.checkpoint()
    return result
  }

  private func enclosureBody(
    of curve: Curve3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CoordinateEnclosure3D {
    if case .surfaceLift(let lift) = curve {
      let box = try lift.boundingBox(
        over: parameters,
        tolerance: tolerance, using: &execution)
      return CoordinateEnclosure3D(
        x: try ScalarInterval(
          lower: box.minimum.x,
          upper: box.maximum.x
        ),
        y: try ScalarInterval(
          lower: box.minimum.y,
          upper: box.maximum.y
        ),
        z: try ScalarInterval(
          lower: box.minimum.z,
          upper: box.maximum.z
        )
      )
    }
    return try DefaultCurveDifferentialEncloser().enclosure(
      of: curve,
      over: parameters,
      tolerance: tolerance, using: &execution
    ).position
  }
}
