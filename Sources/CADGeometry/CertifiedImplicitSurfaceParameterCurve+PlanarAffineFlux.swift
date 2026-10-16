import CADCore

extension CertifiedImplicitSurfaceParameterCurve {
  package func exactPlanarAffineFluxTraversal(
    on surface: BSplineSurface3D,
    reference: Point3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedPlanarAffineFluxTraversal? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try exactPlanarAffineFluxTraversal(on: surface, reference: reference,
      tolerance: tolerance, using: &execution)
  }

  package func exactPlanarAffineFluxTraversal(
    on surface: BSplineSurface3D,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CertifiedPlanarAffineFluxTraversal? {
    try execution.consumeWork(1)
    guard case .bSpline(let firstSurface) = intersection.firstSurface,
      case .bSpline(let secondSurface) = intersection.secondSurface
    else {
      return nil
    }
    guard
      let graph = try ExactIsoparametricPlanarIntersectionGraph.certified(
        first: firstSurface,
        second: secondSurface,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return try graph.planarAffineFluxTraversal(
      curve: self,
      surface: surface,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
  }
}
