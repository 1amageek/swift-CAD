import CADCore

/// One coherent evaluation of an intersection curve and both of its source
/// surface parameterizations. The value prevents downstream consumers from
/// independently refining the same implicit root for the spatial point and
/// each pcurve.
package struct SurfaceSurfaceIntersectionCurveEvaluation: Sendable {
  package let point: Point3D
  package let parameters: SurfaceIntersectionParameterPair
  package let residual: Double

  package init(
    point: Point3D,
    parameters: SurfaceIntersectionParameterPair,
    residual: Double,
    tolerance: ModelingTolerance
  ) throws {
    try point.validate()
    guard residual.isFinite,
      residual >= 0.0,
      residual <= tolerance.distance
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: residual,
        tolerance: tolerance,
        message: "A surface-intersection curve evaluation exceeded its certified residual."
      )
    }
    self.point = point
    self.parameters = parameters
    self.residual = residual
  }
}
